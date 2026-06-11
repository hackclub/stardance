module Admin
  module Raffles
    class ParticipantsController < Admin::ApplicationController
      before_action :set_participant, only: [
        :show, :reject_referrals, :ban_participant, :ban_user, :ban_referred_users,
        :reject_selected, :ban_selected,
        :reject_referral, :ban_referred_user, :clear_fraud, :unclear_fraud
      ]

      def index
        authorize :admin, :access_raffles?

        @query = query_param
        @pagy, @participants = pagy(:offset, participants_scope)
        @participants = @participants.to_a
        @referral_counts = if @participants.any?
          ::Raffle::Referral.where(participant_id: @participants.map(&:id))
                            .group(:participant_id)
                            .count
        else
          {}
        end
      end

      def show
        authorize :admin, :access_raffles?

        @referrals = @participant.referrals
                                 .includes(:referred_user, :credited_week)
                                 .order(created_at: :desc)
      end

      # ── Bulk actions ──────────────────────────────────────────────────

      def reject_referrals
        authorize :admin, :access_raffles?

        count = reject_referrals_for(@participant.referrals.where.not(status: [ :self_referral, :rejected ]))

        redirect_back fallback_location: admin_raffles_participant_path(@participant),
                      allow_other_host: false,
                      notice: "Rejected #{count} referral(s) for #{@participant.display_name}."
      end

      def ban_participant
        authorize :admin, :access_raffles?

        ::PaperTrail.request(whodunnit: current_user.id) do
          @participant.paper_trail_event = "fraud_ban_participant"
          @participant.update!(eligible: false)
        end

        redirect_back fallback_location: admin_raffles_participant_path(@participant),
                      allow_other_host: false,
                      notice: "#{@participant.display_name} removed from raffle."
      end

      def ban_user
        authorize :admin, :access_raffles?

        user = @participant.user
        return redirect_back_with_alert("No linked platform user.") unless user
        return redirect_back_with_alert("#{user.display_name} is already banned.") if user.banned?

        ::PaperTrail.request(whodunnit: current_user.id) do
          ban_platform_user!(user, reason: "Raffle referral fraud")
          @participant.paper_trail_event = "fraud_ban_participant"
          @participant.update!(eligible: false)
        end

        redirect_back fallback_location: admin_raffles_participant_path(@participant),
                      allow_other_host: false,
                      notice: "#{user.display_name} banned from platform."
      end

      def ban_referred_users
        authorize :admin, :access_raffles?

        referrals = @participant.referrals.where.not(status: [ :self_referral, :rejected ])
        rejected, banned = reject_and_ban_referrals(referrals)

        redirect_back fallback_location: admin_raffles_participant_path(@participant),
                      allow_other_host: false,
                      notice: "Rejected #{rejected} referral(s), banned #{banned} user(s)."
      end

      # ── Checkbox actions ──────────────────────────────────────────────

      def reject_selected
        authorize :admin, :access_raffles?

        referrals = selected_referrals
        return redirect_to admin_raffles_participant_path(@participant), alert: "Nothing selected." if referrals.empty?

        count = reject_referrals_for(referrals)

        redirect_to admin_raffles_participant_path(@participant), notice: "Rejected #{count} referral(s)."
      end

      def ban_selected
        authorize :admin, :access_raffles?

        referrals = selected_referrals
        return redirect_to admin_raffles_participant_path(@participant), alert: "Nothing selected." if referrals.empty?

        rejected, banned = reject_and_ban_referrals(referrals)

        redirect_to admin_raffles_participant_path(@participant),
                    notice: "Rejected #{rejected} referral(s), banned #{banned} user(s)."
      end

      # ── Single-referral actions ───────────────────────────────────────

      def reject_referral
        authorize :admin, :access_raffles?

        referral = @participant.referrals.find(params[:referral_id])
        ::PaperTrail.request(whodunnit: current_user.id) do
          referral.paper_trail_event = "fraud_reject"
          referral.update!(status: :rejected, credited_week: nil)
        end

        redirect_to admin_raffles_participant_path(@participant), notice: "Referral rejected."
      end

      def ban_referred_user
        authorize :admin, :access_raffles?

        referral = @participant.referrals.find(params[:referral_id])
        user = referral.referred_user

        return redirect_to admin_raffles_participant_path(@participant), alert: "Already banned." if user&.banned?
        return redirect_to admin_raffles_participant_path(@participant), alert: "No linked user." unless user

        ::PaperTrail.request(whodunnit: current_user.id) do
          referral.paper_trail_event = "fraud_reject"
          referral.update!(status: :rejected, credited_week: nil) unless referral.status_rejected?
          ban_platform_user!(user, reason: "Raffle referral fraud")
        end

        redirect_to admin_raffles_participant_path(@participant),
                    notice: "#{user.display_name} banned, referral rejected."
      end

      # ── Fraud clearing ────────────────────────────────────────────────

      def clear_fraud
        authorize :admin, :access_raffles?

        ::PaperTrail.request(whodunnit: current_user.id) do
          @participant.paper_trail_event = "fraud_cleared"
          @participant.update!(fraud_cleared: true)
        end

        redirect_back fallback_location: admin_raffles_fraud_path,
                      allow_other_host: false,
                      notice: "#{@participant.display_name} marked as safe."
      end

      def unclear_fraud
        authorize :admin, :access_raffles?

        ::PaperTrail.request(whodunnit: current_user.id) do
          @participant.paper_trail_event = "fraud_uncleared"
          @participant.update!(fraud_cleared: false)
        end

        redirect_back fallback_location: admin_raffles_participant_path(@participant),
                      allow_other_host: false,
                      notice: "#{@participant.display_name} back on fraud radar."
      end

      private

      def set_participant
        @participant = ::Raffle::Participant.find(params[:id])
      end

      def selected_referrals
        ids = params[:referral_ids]
        return [] unless ids.is_a?(Array)
        @participant.referrals
                    .where(id: ids.map(&:to_i))
                    .where.not(status: [ :self_referral, :rejected ])
      end

      def reject_referrals_for(scope)
        count = 0
        ::PaperTrail.request(whodunnit: current_user.id) do
          scope.find_each do |referral|
            referral.paper_trail_event = "fraud_bulk_reject"
            referral.update!(status: :rejected, credited_week: nil)
            count += 1
          end
        end
        count
      end

      def reject_and_ban_referrals(scope)
        reason = "Raffle referral fraud (referred by #{@participant.display_name})"
        rejected = 0
        banned = 0

        ::PaperTrail.request(whodunnit: current_user.id) do
          scope.includes(:referred_user).find_each do |referral|
            referral.paper_trail_event = "fraud_bulk_reject"
            referral.update!(status: :rejected, credited_week: nil)
            rejected += 1

            user = referral.referred_user
            next unless user && !user.banned?
            ban_platform_user!(user, reason: reason)
            banned += 1
          end
        end

        [ rejected, banned ]
      end

      def ban_platform_user!(user, reason:)
        user.ban!(reason: reason)
        ::PaperTrail::Version.create!(
          item_type: "User", item_id: user.id, event: "banned",
          whodunnit: current_user.id.to_s,
          object_changes: { banned: [ false, true ], banned_reason: [ nil, reason ] }.to_json
        )
      end

      def redirect_back_with_alert(message)
        redirect_back fallback_location: admin_raffles_participant_path(@participant),
                      allow_other_host: false,
                      alert: message
      end

      def participants_scope
        participants = ::Raffle::Participant.order(created_at: :desc)
        return participants if @query.blank?

        term = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
        participants.left_outer_joins(:user)
                    .where("users.display_name ILIKE :term OR raffle_participants.code ILIKE :term OR raffle_participants.github_login ILIKE :term", term: term)
      end

      def query_param
        value = params[:query].presence || params[:search].presence
        return if value.is_a?(Array) || value.is_a?(ActionController::Parameters)

        value.to_s.strip.first(80).presence
      end
    end
  end
end
