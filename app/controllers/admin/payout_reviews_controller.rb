class Admin::PayoutReviewsController < Admin::ApplicationController
  FILTER_FIELDS = {
    "ship" => { label: "Ship", type: :number },
    "project" => { label: "Project", type: :text },
    "owner" => { label: "Owner", type: :text },
    "shipped" => { label: "Shipped", type: :datetime },
    "votes" => { label: "Votes", type: :number },
    "balance" => { label: "Balance", type: :number },
    "hours" => { label: "Hours", type: :number },
    "percentile" => { label: "Percentile", type: :number },
    "estimate" => { label: "Estimate", type: :number },
    "status" => { label: "Status", type: :text },
    "flags" => { label: "Flags", type: :number }
  }.freeze

  PayoutReviewRow = Data.define(:ship_event, :preview)

  before_action -> { head :not_found unless Post::ShipEvent.payout_feature_enabled?(current_user) }
  before_action :set_body_class

  def index
    authorize :payout_review

    @sample = Post::ShipEvent.payout_score_sample
    ship_events = Post::ShipEvent.ready_for_payout.includes(
      :mission_submission,
      certification_ysws_review: :devlog_reviews,
      post: [ :project, { user: :vote_verdict } ]
    ).to_a

    votes_by_ship = Vote.payout_countable.where(ship_event_id: ship_events.map(&:id)).group(:ship_event_id).count
    flags_by_ship = Vote::Event.pending_vote_flags.where(ship_event_id: ship_events.map(&:id)).group(:ship_event_id).count

    rows = ship_events.map do |ship_event|
      votes_count = votes_by_ship.fetch(ship_event.id, 0)
      pending_flags_count = flags_by_ship.fetch(ship_event.id, 0)
      preview = ship_event.payout_preview(@sample, votes_count:, pending_flags_count:)
      PayoutReviewRow.new(ship_event:, preview:)
    end

    @filter_field = FILTER_FIELDS.key?(params[:filter_field]) ? params[:filter_field] : "estimate"
    @lower_bound = params[:lower_bound].presence
    @upper_bound = params[:upper_bound].presence
    @sort = FILTER_FIELDS.key?(params[:sort]) ? params[:sort] : "estimate"
    @direction = params[:direction] == "asc" ? "asc" : "desc"

    rows = filter_rows(rows)
    rows = sort_rows(rows)

    @pagy, @payout_review_rows = pagy(:offset, rows, limit: 25)
  end

  def show
    @ship_event = Post::ShipEvent.includes(:mission_submission, post: [ :user, :project ]).find(params[:id])
    authorize @ship_event, policy_class: Admin::PayoutReviewPolicy

    @preview = @ship_event.payout_preview
    @votes = @ship_event.votes
                        .includes(:user, :events)
                        .order(:created_at)
    @project_ship_events = @ship_event.project&.ship_events
                                      &.where.not(certification_status: "misfiled")
                                      &.to_a || []
  end

  private

  def filter_rows(rows)
    lower = cast_bound(@lower_bound, @filter_field)
    upper = cast_bound(@upper_bound, @filter_field)
    return rows if lower.nil? && upper.nil?

    rows.select do |row|
      value = comparable_value(row, @filter_field)
      next false if value.nil?

      (lower.nil? || value >= lower) && (upper.nil? || value <= upper)
    end
  end

  def sort_rows(rows)
    populated, empty = rows.partition { |row| comparable_value(row, @sort).present? }
    populated.sort_by! { |row| comparable_value(row, @sort) }
    populated.reverse! if @direction == "desc"
    populated + empty
  end

  def cast_bound(value, field)
    return if value.blank?

    case FILTER_FIELDS.fetch(field)[:type]
    when :number then Float(value)
    when :datetime then Time.zone.parse(value)
    else value.downcase
    end
  rescue ArgumentError, TypeError
    nil
  end

  def comparable_value(row, field)
    ship_event = row.ship_event
    preview = row.preview

    case field
    when "ship" then ship_event.id
    when "project" then ship_event.project&.title&.downcase
    when "owner" then ship_event.payout_recipient&.display_name&.downcase
    when "shipped" then ship_event.post&.created_at
    when "votes" then preview[:votes_count]
    when "balance" then ship_event.payout_recipient&.vote_balance
    when "hours" then preview[:hours]
    when "percentile" then preview[:percentile]
    when "estimate" then preview[:estimated_payout]
    when "status" then preview_status(preview)
    when "flags" then preview[:pending_flags_count]
    end
  end

  def preview_status(preview)
    if preview[:blockers].any?
      "blocked"
    elsif preview[:review_open]
      "review open"
    else
      "ready"
    end
  end

  def set_body_class
    @body_class = "app-layout-page"
  end
end
