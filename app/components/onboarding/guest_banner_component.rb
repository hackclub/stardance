module Onboarding
  class GuestBannerComponent < ViewComponent::Base
    GRACE_PERIOD = 1.day

    def render?
      visitor? || stale_guest?
    end

    def visitor?
      helpers.current_user.nil?
    end

    def stale_guest?
      user = helpers.current_user
      user&.guest? && user.created_at < GRACE_PERIOD.ago
    end
  end
end
