module Raffle
  module Participants
    class Enroll
      def self.run_safely(user)
        new(user).run
      rescue StandardError => e
        Rails.logger.error("[Raffle::Participants::Enroll] #{e.class}: #{e.message}")
        Sentry.capture_exception(e) if defined?(Sentry)
        nil
      end

      def initialize(user)
        @user = user
      end

      def run
        Raffle::Participant.find_or_enroll!(@user)
      end
    end
  end
end
