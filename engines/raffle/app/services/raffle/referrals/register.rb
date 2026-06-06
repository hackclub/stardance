module Raffle
  module Referrals
    class Register
      def self.run_safely(user)
        new(user).run
      rescue StandardError => e
        Rails.logger.error("[Raffle::Referrals::Register] #{e.class}: #{e.message}")
        Sentry.capture_exception(e) if defined?(Sentry)
        nil
      end

      def initialize(user)
        @user = user
      end

      def run
        return if @user.ref.blank?

        match = /\A([rd])-([a-z0-9]{5})\z/.match(@user.ref.strip.downcase)
        return unless match

        participant = Raffle::Participant.find_by(code: match[2])
        return unless participant

        # Self-referral: referred user IS the referrer
        if participant.user_id == @user.id
          Raffle::Referral.create_or_find_by!(referred_user_id: @user.id) do |r|
            r.participant = participant
            r.channel = match[1] == "d" ? "discord" : "web"
            r.raw_ref = match[0]
            r.status = :self_referral
          end
          return
        end

        Raffle::Referral.create_or_find_by!(referred_user_id: @user.id) do |r|
          r.participant = participant
          r.channel = match[1] == "d" ? "discord" : "web"
          r.raw_ref = match[0]
          r.status = :pending
        end
      end
    end
  end
end
