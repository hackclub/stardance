module Raffle
  class DashboardController < ApplicationController
    def show
      try_enroll if signed_in? && !enrolled?
      set_weeks
      set_current_week
      set_board
      set_leaderboard
      return redirect_to(request.path) if @leaderboard.nil?

      @rank_offset = (@pagy.page - 1) * 10

      set_participant_state if enrolled?
      apply_dev_preview if Rails.env.development?
    end

    def claim
      return redirect_to(dashboard_path) unless enrolled?

      week = Raffle::Week.current
      unless week
        return redirect_to(dashboard_path, alert: "No active raffle week.")
      end

      unless current_participant.age_group_teen? && current_participant.hca_linked?
        return redirect_to(dashboard_path, alert: "You need to link your Hack Club account first.")
      end

      claim = Raffle::WeeklyClaim.find_or_initialize_by(participant: current_participant, week: week)
      if claim.new_record?
        claim.save!
        redirect_to dashboard_path, notice: "You claimed your free entry for week #{week.number}!"
      else
        redirect_to dashboard_path, notice: "You already claimed your entry for this week."
      end
    end

    def dev_referrals
      return head :not_found unless Rails.env.development? || Rails.env.test?
      return redirect_to(dashboard_path) unless enrolled?

      kind = referral_kind_param
      count = integer_param(:count, default: 1).clamp(1, 25)
      week = week_from_params || Raffle::Week.current

      count.times do
        user = ::User.create!(
          display_name: "demo-#{SecureRandom.hex(4)}",
          geocoded_country: "US"
        )
        attrs = { participant: current_participant, referred_user: user, channel: "web",
                  status: kind, raw_ref: "r-#{current_participant.code}" }
        if kind == "verified" && week
          attrs.merge!(credited_week: week, verified_at: Time.current)
        end
        Raffle::Referral.create!(attrs)
      end

      redirect_back fallback_location: dashboard_path,
                    allow_other_host: false,
                    notice: "Added #{count} #{kind} referral#{'s' unless count == 1}."
    end

    private

    def try_enroll
      return unless current_user
      Raffle::Participants::Enroll.run_safely(current_user)
      remove_instance_variable(:@current_participant) if defined?(@current_participant)
    end

    def set_weeks
      @board_weeks = Raffle::Week.chronological.to_a
    end

    def set_current_week
      @week = @board_weeks.find(&:status_active?)
      @week_number = @week&.number
      @week_standings = @week ? @week.standings : {}
      @week_pool = @week_standings.values.sum
      @week_participants = @week_standings.size
    end

    def set_board
      @board_week = board_week_from_loaded_weeks || @week
      @board_standings = @board_week == @week ? @week_standings : @board_week&.standings || {}
    end

    def set_leaderboard
      full_board = @board_week ? @board_week.leaderboard(limit: 1000, standings: @board_standings) : []
      @query = text_param(:q)

      if @query.present?
        needle = @query.downcase
        full_board = full_board.select { |participant, _| participant.display_name.to_s.downcase.include?(needle) }
      end

      @pagy, @leaderboard = pagy(:offset, full_board, limit: 10)
    end

    def set_participant_state
      @entry_count = @week_standings[current_participant.id].to_i
      @rank = @week&.rank_for(current_participant, standings: @week_standings)
      @board_rank = @board_week&.rank_for(current_participant, standings: @board_standings)
      @board_you_entries = @board_standings[current_participant.id].to_i
      @claimed_this_week = @week ? current_participant.claimed_week?(@week) : false

      pending = current_participant.pending_referrals
      @pending_count = pending.count
      @pending = pending.includes(:referred_user).limit(6).to_a

      if @board_week
        verified = current_participant.referrals.status_verified.where(credited_week: @board_week)
        @verified_this_week_count = verified.count
        @verified_this_week = verified.includes(:referred_user)
                                      .order(verified_at: :desc)
                                      .limit(6)
                                      .to_a
      else
        @verified_this_week_count = 0
        @verified_this_week = []
      end
    end

    def board_week_from_loaded_weeks
      @selected_week_number = integer_param(:lb_week)
      return unless @selected_week_number

      @board_weeks.find { |week| week.number == @selected_week_number }
    end

    def week_from_params
      week_number = @selected_week_number || integer_param(:lb_week)
      return unless week_number

      Raffle::Week.find_by(number: week_number)
    end

    def apply_dev_preview
      return if params.keys.none? { |k| k.to_s.start_with?("dev_") }

      @week_number = integer_param(:dev_week, min: 1, max: 16) if params[:dev_week].present?
      @entry_count = integer_param(:dev_entries, min: 0) if params[:dev_entries].present?
      @week_pool = integer_param(:dev_pool, min: 0) if params[:dev_pool].present?
      @week_participants = integer_param(:dev_entrants, min: 0) if params[:dev_entrants].present?
      @rank = integer_param(:dev_rank, min: 1) if params.key?(:dev_rank)
    end

    def referral_kind_param
      params[:kind] == "verified" ? "verified" : "pending"
    end

    def integer_param(name, default: nil, min: nil, max: nil)
      value = Integer(params[name], exception: false)
      value = default if value.nil?
      return if value.nil?

      value = [ value, min ].max if min
      value = [ value, max ].min if max
      value
    end

    def text_param(name, max_length: 80)
      value = params[name]
      return if value.is_a?(Array) || value.is_a?(ActionController::Parameters)

      value = value.to_s.strip
      value = value.first(max_length)
      value.presence
    end
  end
end
