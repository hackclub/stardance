class Cache::LandingCountsJob < ApplicationJob
  queue_as :literally_whenever

  def perform
    Rails.logger.info "Warming up landing page RSVP and signup counts..."

    Rails.cache.fetch("landing/rsvp_count", expires_in: 30.seconds, force: true) do
      Rsvp.count
    end

    Rails.cache.fetch("landing/signup_count", raw: true, expires_in: 30.seconds, force: true) do
      LandingController.deduplicated_signup_count
    end

    Rails.logger.info "Landing page RSVP and signup counts warmed."
  end
end
