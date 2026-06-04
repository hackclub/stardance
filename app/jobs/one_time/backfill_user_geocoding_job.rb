class OneTime::BackfillUserGeocodingJob < ApplicationJob
  queue_as :literally_whenever

  SIGNUP_REQUEST_WINDOW = 15.seconds
  SIGNUP_REQUEST_CONTROLLERS = {
    "Onboarding::WizardController" => "start",
    "SessionsController" => "create"
  }.freeze

  def scope = User.where(geocoded_country: nil).where.not(ip_address: [ nil, "" ])

  def perform
    rsvp_count = copy_from_matching_rsvps
    active_insights_count = copy_from_active_insights
    enqueued_count = enqueue_missing_geocoding

    Rails.logger.info "[BackfillUserGeocoding] Copied #{rsvp_count} users from RSVPs; copied #{active_insights_count} users from Active Insights; enqueued #{enqueued_count} geocode jobs"
  end

  private

  def copy_from_matching_rsvps
    count = 0

    User.where.not(email: [ nil, "" ]).find_each do |user|
      rsvp = matching_rsvp_for(user)
      next unless rsvp

      changes = missing_signup_geo_attrs(user, rsvp)
      next if changes.empty?

      user.update_columns(changes)
      count += 1
    end

    count
  end

  def copy_from_active_insights
    return 0 unless defined?(ActiveInsights::Request)

    count = 0

    User.where(ip_address: [ nil, "" ]).find_each do |user|
      request = closest_signup_request_for(user)
      next unless request

      changes = {
        ip_address: request.ip_address,
        user_agent: request.user_agent
      }.select { |attribute, value| user.public_send(attribute).blank? && value.present? }
      next if changes.empty?

      user.update_columns(changes)
      count += 1
    end

    count
  end

  def closest_signup_request_for(user)
    return if user.created_at.blank?

    candidates = signup_requests
      .where(started_at: (user.created_at - SIGNUP_REQUEST_WINDOW)..(user.created_at + SIGNUP_REQUEST_WINDOW))
      .where.not(ip_address: [ nil, "" ])
      .order(signup_request_distance_sql(user), :started_at, :id)
      .limit(2)
      .to_a

    return if candidates.empty?
    return candidates.first if candidates.one?

    first_distance = signup_request_distance(candidates.first, user)
    second_distance = signup_request_distance(candidates.second, user)
    return candidates.first if second_distance - first_distance >= 5.seconds

    nil
  end

  def signup_request_distance_sql(user)
    timestamp = ActiveRecord::Base.connection.quote(user.created_at)
    Arel.sql("ABS(EXTRACT(EPOCH FROM (started_at - TIMESTAMP #{timestamp}))) ASC")
  end

  def signup_request_distance(request, user)
    (request.started_at - user.created_at).abs
  end

  def signup_requests
    SIGNUP_REQUEST_CONTROLLERS.reduce(ActiveInsights::Request.none) do |scope, (controller, action)|
      scope.or(ActiveInsights::Request.where(controller: controller, action: action))
    end
  end

  def matching_rsvp_for(user)
    Rsvp.where("LOWER(email) = ?", user.email.downcase)
        .where.not(ip_address: [ nil, "" ])
        .order(:created_at)
        .first
  end

  def missing_signup_geo_attrs(user, rsvp)
    {
      ip_address: rsvp.ip_address,
      user_agent: rsvp.user_agent,
      geocoded_lat: rsvp.geocoded_lat,
      geocoded_lon: rsvp.geocoded_lon,
      geocoded_country: rsvp.geocoded_country,
      geocoded_subdivision: rsvp.geocoded_subdivision
    }.select { |attribute, value| user.public_send(attribute).blank? && value.present? }
  end

  def enqueue_missing_geocoding
    count = 0
    scope.find_each do |user|
      UserGeocodeJob.perform_later(user.id)
      count += 1
    end

    count
  end
end
