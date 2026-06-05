module Raffle
  module ReferralTrackable
    extend ActiveSupport::Concern

    included do
      after_create_commit :raffle_on_signup
    end

    private

    def raffle_on_signup
      Raffle::Participants::Enroll.run_safely(self)
      Raffle::Referrals::Register.run_safely(self)
    end
  end
end
