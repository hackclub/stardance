class Api::V1::Certification::ShipsController < Api::V1::Certification::BaseController
  class InvalidParam < StandardError; end

  rescue_from InvalidParam do |error|
    render json: { error: error.message }, status: :bad_request
  end

  # GET /api/v1/certification/ships
  #
  # Returns ship certification reviews within a time window (default: the last 24 hours).
  #
  # Query params:
  #   hours (positive integer, default 24; ignored when since is given)
  #   since (ISO 8601 datetime)
  #   until (ISO 8601 datetime, default now)
  #   status (pending|approved|returned|all, default all)
  def index
    window_start, window_end = parse_time_window
    status_filter = params[:status].presence_in(%w[pending approved returned]) || "all"

    scope = ::Certification::Ship
      .joins(:project)
      .where(projects: { deleted_at: nil })
      .where(created_at: window_start..window_end)
      .includes(:reviewer, project: { memberships: :user })
    scope = scope.where(status: status_filter) unless status_filter == "all"

    ships = scope.order(created_at: :desc).map { |ship| serialize_ship(ship) }

    render json: {
      window: { from: window_start.iso8601, to: window_end.iso8601 },
      status_filter: status_filter,
      count: ships.size,
      ships: ships
    }
  end

  private

  def parse_time_window
    window_end = parse_time_param(:until) || Time.current
    window_start = parse_time_param(:since) || window_end - window_hours.hours
    raise InvalidParam, "since must be earlier than until" if window_start > window_end

    [ window_start, window_end ]
  end

  def window_hours
    return 24 if params[:hours].blank?

    hours = Integer(params[:hours], exception: false)
    raise InvalidParam, "hours must be a positive integer" unless hours&.positive?

    hours
  end

  def parse_time_param(key)
    value = params[key]
    return nil if value.blank?

    Time.zone.parse(value.to_s) || raise(InvalidParam, "#{key} is not a valid ISO 8601 datetime")
  rescue ArgumentError, TypeError
    raise InvalidParam, "#{key} is not a valid ISO 8601 datetime"
  end

  def serialize_ship(ship)
    project = ship.project
    owner_membership = project.memberships.find { |m| m.role == "owner" }
    owner = owner_membership&.user
    reviewer = ship.reviewer

    {
      id: ship.id,
      status: ship.status,
      created_at: ship.created_at.iso8601,
      updated_at: ship.updated_at.iso8601,
      decided_at: ship.decided_at&.iso8601,
      claimed_at: ship.claimed_at&.iso8601,
      feedback: ship.feedback,
      project: {
        id: project.id,
        title: project.title,
        ship_status: project.ship_status,
        demo_url: project.demo_url,
        repo_url: project.repo_url,
        description: project.description,
        duration_seconds: project.duration_seconds,
        shipped_at: project.shipped_at&.iso8601
      },
      owner: owner ? {
        id: owner.id,
        display_name: owner.display_name,
        slack_id: owner.slack_id
      } : nil,
      reviewer: reviewer ? {
        id: reviewer.id,
        display_name: reviewer.display_name,
        slack_id: reviewer.slack_id
      } : nil
    }
  end
end
