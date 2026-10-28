module Admin
  # The Finality ship-early event: who shipped on each bonus day, what their
  # bonus came to, and the raffle pool. Rules live in app/models/finality.rb.
  class FinalityController < Admin::ApplicationController
    def show
      authorize :finality

      @ship_events = Finality.ships.to_a
      @raffle_entry_ids = Finality.raffle_entry_ids(@ship_events)
      @days = Finality::BONUS_RATES.map do |day, rate|
        on_day = @ship_events.select { |ship_event| Finality.ship_day(ship_event) == day }
        { day: day, rate: rate, ships: on_day.size, people: on_day.filter_map { |ship_event| ship_event.payout_recipient&.id }.uniq.size }
      end
      @bonus_paid = @ship_events.sum { |ship_event| Finality.bonus_entry(ship_event)&.amount.to_i }
      @unpaid_count = @ship_events.count { |ship_event| Finality.bonus_for(ship_event).to_i.positive? && Finality.bonus_entry(ship_event).nil? }
      @pending_count = @ship_events.count { |ship| ship.certification_status != "approved" && !Finality.raffle_ineligible?(ship) }
      @participant_count = @ship_events.select { |ship| @raffle_entry_ids.include?(ship.id) }.map { |ship| ship.post.user_id }.uniq.size
      @draw = Finality::RaffleDraw.current
      @prize = Finality.raffle_prize(params[:prize]) || Finality::RAFFLE_PRIZES.first
      @selections = @draw ? @draw.selections.includes(:user, :selected_by, :voided_by).order(created_at: :desc, id: :desc).to_a : []
      @active_selections = @selections.reject(&:voided_at?)
      @prize_selections = @active_selections.select { |selection| selection.prize_key == @prize[:key] }.index_by(&:slot)
      @available_count = @draw&.frozen_at? ? @draw.available_entry_counts.size : @participant_count
    end

    def award
      authorize :finality

      awarded = Finality.award_missing!
      ::PaperTrail::Version.create!(
        item_type: "User",
        item_id: current_user.id,
        event: "finality_bonus_award",
        whodunnit: current_user.id,
        object_changes: { awarded: awarded }.to_json
      )

      redirect_to admin_finality_path, notice: "Finality bonuses awarded: #{awarded}."
    end

    def freeze_pool
      authorize :finality

      draw = Finality::RaffleDraw.freeze_pool!(actor: current_user)
      redirect_to admin_finality_path, notice: "Entry pool frozen: #{draw.entry_count} entries from #{draw.participant_count} people.", status: :see_other
    rescue Finality::RaffleDraw::Error => error
      redirect_to admin_finality_path, alert: error.message, status: :see_other
    end

    def roll
      authorize :finality

      count = prepared_draw.roll!(prize_key: params[:prize_key], actor: current_user)
      redirect_to admin_finality_path(prize: params[:prize_key]), notice: "#{count} selections saved. Nobody has been notified.", status: :see_other
    rescue Finality::RaffleDraw::Error => error
      redirect_to admin_finality_path(prize: params[:prize_key]), alert: error.message, status: :see_other
    end

    def reroll
      authorize :finality

      replacement = prepared_draw.reroll!(selection_id: params[:selection_id], reason: params[:reason], actor: current_user)
      redirect_to admin_finality_path(prize: replacement.prize_key), notice: "Replacement saved and previous selection excluded. Nobody has been notified.", status: :see_other
    rescue Finality::RaffleDraw::Error => error
      redirect_to admin_finality_path(prize: params[:prize_key]), alert: error.message, status: :see_other
    end

    private

    def prepared_draw
      Finality::RaffleDraw.current || raise(Finality::RaffleDraw::Error, "Freeze the approved entry pool first.")
    end
  end
end
