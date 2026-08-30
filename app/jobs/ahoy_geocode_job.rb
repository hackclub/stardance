# frozen_string_literal: true

class AhoyGeocodeJob < ApplicationJob
  queue_as :literally_whenever
  limits_concurrency to: 1, key: "ahoy_geocode", duration: 1.second

  def perform(visit_id)
    return unless ENV["AHOY_DB_URL"].present? && ENV["GEOCODER_HC_API_KEY"].present?

    visit = Ahoy::Visit.find_by(id: visit_id)
    return unless visit && visit.ip.present?
    return if visit.city.present?

    result = HackclubGeocoder.geocode_ip(visit.ip)
    return unless result

    visit.update!(
      city: result[:city],
      region: result[:region],
      country: result[:country],
      latitude: result[:latitude],
      longitude: result[:longitude]
    )
  end
end
