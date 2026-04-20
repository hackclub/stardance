class OneTime::BackfillRsvpGeocodingJob < ApplicationJob
  queue_as :literally_whenever

  def scope = Rsvp.where(geocoded_country: nil).where.not(ip_address: [ nil, "" ])

  def perform
    count = 0

    scope.find_each do |rsvp|
      RsvpGeocodeJob.perform_later(rsvp.id)
      count += 1
    end

    Rails.logger.info "[BackfillRsvpGeocoding] Enqueued #{count} geocode jobs"
  end
end
