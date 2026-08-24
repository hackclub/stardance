# frozen_string_literal: true

# The two-stage hardware review dash (design funding + build certification),
# shared between the global reviewer queue (Admin::Certification::HardwareReviews)
# and a mission's own queue (Admin::Missions::HardwareReviews). The host controller
# supplies which projects it covers, how to authorize, and the route helpers; the
# queue building, stats, leaderboards and review context live here.
#
# Host controllers must implement:
#   reviewable_projects            -> a Project relation (the hardware projects this dash reviews)
#   authorize_hardware_queue       -> per-action auth for the list/next actions
#   authorize_hardware_review(project)
#   hardware_review_path(project)
#   hardware_queue_path(stage)     -> "design" | "build"
#   hardware_next_path(stage:, skip: nil)
module HardwareReviewQueue
  extend ActiveSupport::Concern

  included do
    before_action :set_body_class
    before_action :release_other_claims, only: [ :next ]
    helper_method :hardware_review_path, :hardware_queue_path, :hardware_next_path,
                  :hardware_skip_path, :hardware_queue_title, :hardware_back_link,
                  :hardware_flag_for_fraud_path, :undo_review_path
  end

  def design
    authorize_hardware_queue
    load_queue(:design)
    render "admin/certification/hardware_reviews/queue"
  end

  def build
    authorize_hardware_queue
    load_queue(:build)
    render "admin/certification/hardware_reviews/queue"
  end

  # Stays within the queue the reviewer started from, so "Start reviewing" on the
  # design queue never hands them a build certification.
  def next
    authorize_hardware_queue

    stage = params[:stage].presence_in(%w[design build]) || "design"
    skip = parse_skip_tokens
    candidate = next_candidate(skip, stage)
    if candidate.nil?
      redirect_to hardware_queue_path(stage), notice: "#{stage.capitalize} queue is empty." and return
    end

    claimed = claim_candidate(candidate)
    if claimed
      redirect_to hardware_review_path(claimed.project_id)
    else
      redirect_to hardware_next_path(stage: stage, skip: (skip[:tokens] + [ candidate[:token] ]).join(","))
    end
  end

  # A reviewer passing on a submission. Records a per-reviewer skip so the queue
  # keeps it out of *their* next-up for the cooldown window, then rejoins the
  # normal `next` flow — whose release_other_claims hands the claim back so
  # another reviewer can pick it up right away.
  def skip
    authorize_hardware_queue

    stage = params[:stage].presence_in(%w[design build]) || "design"
    record = skip_target
    ::Certification::ReviewSkip.record!(user: current_user, reviewable: record) if record

    redirect_to hardware_next_path(stage: stage)
  end

  def show
    authorize_hardware_review(@project)
    load_review_context
    render "admin/certification/hardware_reviews/show"
  end

  # Flags the project for the fraud team. Reuses Project::Report's existing fraud
  # machinery — the model's after_commit fires the Slack notify and PaperTrail
  # records the flag. No verdict is recorded and the project stays visible;
  # this is a heads-up, not a review action. Idempotent on the unique
  # (reporter_id, project_id) index.
  def flag_for_fraud
    authorize_hardware_review(@project)

    report = ::Project::Report.new(
      project: @project,
      reporter: current_user,
      reason: "fraud",
      details: params[:details].to_s.strip,
      status: :pending
    )

    if report.save
      redirect_to hardware_review_path(@project),
                  notice: "Flagged for fraud review. The fraud team has been notified."
    elsif report.errors.of_kind?(:reporter_id, :taken)
      redirect_to hardware_review_path(@project),
                  notice: "You've already flagged this project for fraud."
    else
      redirect_to hardware_review_path(@project),
                  alert: report.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to hardware_review_path(@project),
                notice: "You've already flagged this project for fraud."
  end

  private

  # Asking for the next review hands the current one back. Without this a
  # skipped submission stays claimed for the full CLAIM_TTL and no other
  # reviewer can pick it up, since `available_for` only offers unclaimed rows.
  # Both models, because one dash spans both queues. Mirrors the software ship
  # queue (Admin::Certification::ShipsController#release_other_claims).
  def release_other_claims
    return if current_user.blank?

    ::Certification::FundingRequest.release_all_for(current_user)
    ::Certification::Ship.release_all_for(current_user)
  end

  def load_queue(stage)
    @stage = stage.to_s
    @status = params[:status].presence_in(%w[pending approved returned all]) || "pending"
    @sort = params[:sort] == "newest" ? "newest" : "oldest"
    @search = params[:search].to_s.strip
    @from = parse_date(params[:from])
    @to = parse_date(params[:to])
    @lb_period = params[:lb].presence_in(%w[daily weekly alltime]) || "daily"

    @review_items = sort_review_items(queue_items(@stage))
    @hackpad_project_ids = hackpad_project_ids(@review_items.map { |item| item[:project].id })
    @stats = stage_stats(@stage)
    @tab_counts = {
      "design" => stage_list_scope("design").pending.count,
      "build" => stage_list_scope("build").pending.count
    }
    @leaderboards = {
      "daily" => hardware_leaderboard(:daily),
      "weekly" => hardware_leaderboard(:weekly),
      "alltime" => hardware_leaderboard(:alltime)
    }
    @my_stats = my_hardware_stats
  end

  # The reviewer's own numbers, scoped to the projects this dash covers.
  def my_hardware_stats
    design = ::Certification::FundingRequest.where(reviewer: current_user, project: reviewable_projects).decided
    build = ::Certification::Ship.where(reviewer: current_user, project: reviewable_projects).decided
    today = Time.current.beginning_of_day

    {
      design: decision_tally(design),
      build: decision_tally(build),
      stardust: design.sum(:stardust_earned).to_f + build.sum(:stardust_earned).to_f,
      today: design.where(decided_at: today..).count + build.where(decided_at: today..).count
    }
  end

  def decision_tally(scope)
    by_status = scope.group(:status).count
    approved = by_status["approved"].to_i
    returned = by_status["returned"].to_i
    total = approved + returned

    {
      total: total,
      approved: approved,
      returned: returned,
      approval_rate: total.zero? ? nil : (approved * 100.0 / total).round
    }
  end

  def stage_model(stage)
    stage.to_s == "design" ? ::Certification::FundingRequest : ::Certification::Ship
  end

  def stage_list_scope(stage)
    stage.to_s == "design" ? hardware_funding_list_scope : hardware_ship_list_scope
  end

  def queue_items(stage)
    scope = apply_queue_filters(stage_list_scope(stage), stage_model(stage))

    if stage == "design"
      scope.includes(:reviewer, project: { memberships: :user }).map do |request|
        review_item(:funding, request, request.project, request.owner, request.created_at)
      end
    else
      scope.includes(:reviewer, :post_ship_event, project: { memberships: :user }).map do |ship|
        review_item(:ship, ship, ship.project, ship.owner, ship.created_at)
      end
    end
  end

  def review_owner
    @review_owner ||= @project.memberships.owner.first&.user
  end

  def load_review_context
    @funding_request = @project.latest_funding_request
    @ship = @project.latest_ship_review
    @owner = review_owner
    @active_review =
      if @funding_request&.pending?
        @funding_request
      elsif @ship&.pending?
        @ship
      end
    @active_review_type =
      case @active_review
      when ::Certification::FundingRequest then :funding
      when ::Certification::Ship then :ship
      end
    @past_reviews = past_reviews
    load_undo_context
    @lapse_timelapses = lapse_timelapses_for_review
    @lookout_recordings = lookout_recordings_for_review
  end

  # Only the newest decided review is reversible, so the undo affordance and its
  # preflight ledger are computed for @past_reviews.first alone. The preflight
  # can make an HCB round trip (to check a grant), so it's skipped entirely for
  # anyone not allowed to undo.
  def load_undo_context
    latest_decided = @past_reviews.first
    return unless latest_decided&.decided?
    return unless can_undo_review?(latest_decided)

    @undo_review = latest_decided
    @undo_preflight = ::Certification::ReviewUndoer.new(latest_decided).preflight
  end

  def can_undo_review?(review)
    undo_policy_for(review).undo?
  end

  def undo_policy_for(review)
    klass = review.is_a?(::Certification::FundingRequest) ?
      Admin::Certification::FundingRequestPolicy : Admin::Certification::ShipPolicy
    klass.new(current_user, review)
  end

  def undo_review_path(review)
    if review.is_a?(::Certification::FundingRequest)
      undo_admin_certification_funding_request_path(review)
    else
      undo_admin_certification_ship_path(review)
    end
  end

  # Every decided funding request and ship for this project, newest first. The
  # active (pending) review is left out - it's the thing being decided - except a
  # reversed one: a funding undo sends the record back to pending, so it would be
  # the active review, yet we still want it in the history with a "Reversed" badge
  # rather than silently vanishing.
  def past_reviews
    reviews = @project.certification_funding_requests.includes(:reviewer).to_a +
              @project.ship_reviews.includes(:reviewer).to_a
    reviews
      .reject { |review| (review.pending? || review == @active_review) && review.reversed_at.blank? }
      .sort_by(&:created_at)
      .reverse
  end

  def hardware_funding_scope
    ::Certification::FundingRequest.available_for(current_user).not_skipped_by(current_user)
      .joins(:project).where(project: reviewable_projects)
  end

  def hardware_ship_scope
    ::Certification::Ship.available_for(current_user).not_skipped_by(current_user)
      .joins(:project).where(project: reviewable_projects)
  end

  def hardware_funding_list_scope
    ::Certification::FundingRequest.for_reviewer(current_user).joins(:project).where(project: reviewable_projects)
  end

  def hardware_ship_list_scope
    ::Certification::Ship.for_reviewer(current_user).joins(:project).where(project: reviewable_projects)
  end

  def review_item(type, record, project, owner, submitted_at)
    {
      type: type,
      stage: type == :funding ? "design" : "build",
      stage_label: type == :funding ? "Design" : "Build",
      record: record,
      project: project,
      owner: owner,
      submitted_at: submitted_at,
      token: "#{type}:#{record.id}"
    }
  end

  # Of the given project ids, those whose active mission is Hackpad - so the
  # queue can flag them with a pill without an N+1. Returns a Set.
  def hackpad_project_ids(project_ids)
    return Set.new if project_ids.empty?

    Project::MissionAttachment.active
      .joins(:mission)
      .where(missions: { slug: "hackpad" }, project_id: project_ids)
      .pluck(:project_id)
      .to_set
  end

  def stage_stats(stage)
    scope = stage_list_scope(stage)
    model = stage_model(stage)
    sla_days = model::SLA_DAYS
    today = Time.current.beginning_of_day
    oldest = scope.pending.order(:created_at).first

    {
      pending: scope.pending.count,
      oldest_pending: oldest && review_item(
        stage == "design" ? :funding : :ship, oldest, oldest.project, oldest.owner, oldest.created_at
      ),
      overdue_pending: scope.pending.where("#{model.table_name}.created_at < ?", Time.current - sla_days.days).count,
      sla_days: sla_days,
      decisions_today: scope.decided.where(decided_at: today..).count,
      new_today: scope.where(created_at: today..).count
    }
  end

  def apply_queue_filters(scope, model)
    scope = scope.where(status: @status) unless @status == "all"
    scope = scope.where("#{model.table_name}.created_at >= ?", @from.beginning_of_day) if @from
    scope = scope.where("#{model.table_name}.created_at <= ?", @to.end_of_day) if @to
    return scope if @search.blank?

    if @search.match?(/\A\d+\z/)
      scope.where("#{model.table_name}.id = :id OR projects.title ILIKE :q", id: @search.to_i, q: "%#{@search}%")
    else
      scope.where("projects.title ILIKE ?", "%#{@search}%")
    end
  end

  def sort_review_items(items)
    sorted = items.sort_by { |item| item[:submitted_at] || Time.zone.at(0) }
    @sort == "newest" ? sorted.reverse : sorted
  end

  def hardware_leaderboard(period, now: Time.current, limit: 10)
    rows = Hash.new(0)
    [ ::Certification::FundingRequest, ::Certification::Ship ].each do |model|
      scope = model.joins(:reviewer)
        .where.not(reviewer_id: nil)
        .decided
        .where(project: reviewable_projects)
      case period.to_sym
      when :daily then scope = scope.where(decided_at: now.beginning_of_day..)
      when :weekly then scope = scope.where(decided_at: now.beginning_of_week..)
      end
      scope.group("users.display_name").count.each do |name, count|
        rows[name] += count
      end
    end
    rows.sort_by { |name, count| [ -count, name ] }.first(limit).map { |name, count| { name: name, count: count } }
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # The submission behind a "funding:ID" / "ship:ID" skip token.
  def skip_target
    type, id = params[:token].to_s.split(":", 2)
    case type
    when "funding" then ::Certification::FundingRequest.find_by(id: id)
    when "ship" then ::Certification::Ship.find_by(id: id)
    end
  end

  def parse_skip_tokens
    tokens = params[:skip].to_s.split(",").map(&:strip).reject(&:blank?).uniq
    {
      tokens: tokens,
      funding_ids: tokens.filter_map { |token| token.delete_prefix("funding:").to_i if token.start_with?("funding:") },
      ship_ids: tokens.filter_map { |token| token.delete_prefix("ship:").to_i if token.start_with?("ship:") }
    }
  end

  def next_candidate(skip, stage)
    if stage == "design"
      scope = hardware_funding_scope
      scope = scope.where.not(id: skip[:funding_ids]) if skip[:funding_ids].any?
      record = scope.order(claim_order_sql(::Certification::FundingRequest), :created_at).first
      record && review_item(:funding, record, record.project, record.owner, record.created_at)
    else
      scope = hardware_ship_scope
      scope = scope.where.not(id: skip[:ship_ids]) if skip[:ship_ids].any?
      record = scope.order(claim_order_sql(::Certification::Ship), :created_at).first
      record && review_item(:ship, record, record.project, record.owner, record.created_at)
    end
  end

  def claim_candidate(candidate)
    case candidate[:type]
    when :funding
      ::Certification::FundingRequest.atomic_claim!(candidate[:record].id, current_user)
    when :ship
      ::Certification::Ship.atomic_claim!(candidate[:record].id, current_user)
    end
  end

  def claim_order_sql(model)
    Arel.sql(model.sanitize_sql_array([ "CASE WHEN reviewer_id = ? THEN 0 ELSE 1 END", current_user.id ]))
  end

  # Provider URLs expire after ~1h, so a short cache keyed by project kills the
  # per-render HTTP fan-out without staling them.
  RECORDINGS_CACHE_TTL = 1.minute

  def lapse_timelapses_for_review
    Rails.cache.fetch([ "hardware_review_recordings", "lapse", @project.id ], expires_in: RECORDINGS_CACHE_TTL) do
      LapseService.timelapses_for_project(
        hackatime_user_id: review_owner&.hackatime_identity&.uid,
        project_keys: @project.hackatime_keys
      )
    end
  end

  def lookout_recordings_for_review
    Rails.cache.fetch([ "hardware_review_recordings", "lookout", @project.id ], expires_in: RECORDINGS_CACHE_TTL) do
      LookoutService.recordings_for_project(@project)
    end
  end

  # The .app-layout wrapper reserves the sidebar gutter itself; this body class
  # zeroes the body's own sidebar margin so the two don't stack into a huge gap.
  def set_body_class
    @body_class = "app-layout-page"
  end
end
