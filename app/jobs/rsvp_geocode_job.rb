# frozen_string_literal: true

class RsvpGeocodeJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 5, key: "rsvp_geocode", duration: 1.second

  def perform(rsvp_id)
    return unless ENV["GEOCODER_HC_API_KEY"].present?

    rsvp = Rsvp.find_by(id: rsvp_id)
    return unless rsvp && rsvp.ip_address.present?
    return if rsvp.geocoded_country.present?

    result = HackclubGeocoder.geocode_ip(rsvp.ip_address)
    return unless result

    rsvp.update!(
      geocoded_lat: result[:latitude],
      geocoded_lon: result[:longitude],
      geocoded_country: result[:country],
      geocoded_subdivision: result[:region]
    )
  end
end
