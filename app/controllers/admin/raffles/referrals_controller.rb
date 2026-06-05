module Admin
  module Raffles
    class ReferralsController < Admin::ApplicationController
      before_action :set_referral, only: [ :update ]

      def index
        authorize :admin, :access_raffles?

        @status = status_param
        @pagy, @referrals = pagy(:offset, referrals_scope)
      end

      def update
        authorize :admin, :access_raffles?

        case status_param
        when "verified"
          week = ::Raffle::Week.current
          unless week
            return redirect_back fallback_location: admin_raffles_referrals_path,
                                 allow_other_host: false,
                                 alert: "Open a raffle week before verifying referrals."
          end

          @referral.paper_trail_event = "manual_verify"
          @referral.update!(status: :verified, credited_week: week, verified_at: Time.current)
        when "rejected"
          @referral.paper_trail_event = "manual_reject"
          @referral.update!(status: :rejected, credited_week: nil)
        when "pending"
          @referral.paper_trail_event = "manual_reset"
          @referral.update!(status: :pending, credited_week: nil, verified_at: nil)
        else
          return redirect_back fallback_location: admin_raffles_referrals_path,
                               allow_other_host: false,
                               alert: "Unknown referral status."
        end

        redirect_back fallback_location: admin_raffles_referrals_path,
                      allow_other_host: false,
                      notice: "Referral updated."
      end

      private

      def set_referral
        @referral = ::Raffle::Referral.find(params[:id])
      end

      def referrals_scope
        referrals = ::Raffle::Referral.includes(:participant, :referred_user, :credited_week)
                                      .order(created_at: :desc)
        @status.present? ? referrals.where(status: @status) : referrals
      end

      def status_param
        value = params[:status]
        return if value.is_a?(Array) || value.is_a?(ActionController::Parameters)

        value if ::Raffle::Referral.statuses.key?(value)
      end
    end
  end
end
