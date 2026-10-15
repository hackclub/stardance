module Raffle
  module Referrals
    # Converts a pending referral when the referred user links their Hack Club
    # account. Credits the referrer with entries for the active week, if any.
    class Credit
      def self.run_safely(user)
        new(user).run
      rescue StandardError => e
        Rails.logger.error("[Raffle::Referrals::Credit] #{e.class}: #{e.message}")
        Rails.error.report(e)
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

          referral.paper_trail_event = "credit_referral"
          referral.update!(
            status: :verified,
            credited_week: Raffle::Week.current,
            verified_at: Time.current
          )

          referral.participant.user&.sync_referral_achievements!

          referral
        end
      end
    end
  end
end
