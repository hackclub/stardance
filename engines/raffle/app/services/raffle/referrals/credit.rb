module Raffle
  module Referrals
    # Converts a pending referral when the referred user links their Hack Club
    # account. Credits the referrer with entries for the currently-active week.
    class Credit
      def self.run_safely(user)
        new(user).run
      rescue StandardError => e
        Rails.logger.error("[Raffle::Referrals::Credit] #{e.class}: #{e.message}")
        Sentry.capture_exception(e) if defined?(Sentry)
        nil
      end

      def initialize(user)
        @user = user
      end

      def run
        return unless @user

        referral = Raffle::Referral.includes(:participant).find_by(
          referred_user_id: @user.id,
          status: :pending
        )
        return unless referral

        referral.with_lock do
          return referral unless referral.status_pending?

          week = Raffle::Week.current
          return unless week

          referral.paper_trail_event = "credit_referral"
          referral.update!(
            status: :verified,
            credited_week: week,
            verified_at: Time.current
          )
          referral
        end
      end
    end
  end
end
