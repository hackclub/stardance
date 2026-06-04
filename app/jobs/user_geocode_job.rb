# frozen_string_literal: true

class UserGeocodeJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 5, key: "user_geocode", duration: 1.second

  def perform(user_id)
    return unless ENV["GEOCODER_HC_API_KEY"].present?

    user = User.find_by(id: user_id)
    return unless user && user.ip_address.present?
    return if user.geocoded_country.present?

    result = HackclubGeocoder.geocode_ip(user.ip_address)
    return unless result

    user.update!(
      geocoded_lat: result[:latitude],
      geocoded_lon: result[:longitude],
      geocoded_country: result[:country],
      geocoded_subdivision: result[:region]
    )
  end
end
