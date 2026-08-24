class Admin::Certification::ShipsController < Admin::Certification::ApplicationController
  include HardwareReviewUndoable

  before_action :release_other_claims, only: [ :next ]
  before_action :set_ship, only: [ :show, :update, :set_project_type, :set_bonus_stardust, :report_fraud,
                                   :flag_queue_mismatch, :undo ]
  before_action :set_submitter_context, only: [ :show, :update ]
  before_action :set_body_class, only: [ :index, :show, :update, :logs ]

  def index
    authorize ::Certification::Ship

    @status       = params[:status].presence_in(%w[pending approved returned all]) || "pending"
    @sort         = params[:sort] == "newest" ? "newest" : "oldest"
    @search       = params[:search].to_s.strip
    @from         = parse_date(params[:from])
    @to           = parse_date(params[:to])
    @project_type = params[:project_type].presence

    scope = policy_scope(::Certification::Ship)
    scope = scope.where(status: @status) unless @status == "all"
    scope = scope.where("certification_ship_reviews.created_at >= ?", @from.beginning_of_day) if @from
    scope = scope.where("certification_ship_reviews.created_at <= ?", @to.end_of_day) if @to
    scope = apply_search(scope) if @search.present?

    @type_counts = scope.joins(:project).group("projects.project_type").count

    scope = scope.by_project_type(@project_type) if @project_type.present?

    @pagy, @ships = pagy(:offset,
                         scope.includes(
                           :reviewer, :returned_by,
                           project: {
                             memberships: :user,
                             posts: :postable
                           }
                         ).order(created_at: @sort == "newest" ? :desc : :asc),
                         limit: 25)

    @own_project_ids = current_user.memberships.pluck(:project_id).to_set
    @internal_sw_dash_reviews_disabled = internal_sw_dash_reviews_disabled?

    @stats = ::Certification::Ship.dashboard_stats
    @lb_period = params[:lb].presence_in(%w[daily weekly alltime]) || "daily"
    @leaderboards = {
      "daily" => ::Certification::Ship.leaderboard(:daily),
      "weekly" => ::Certification::Ship.leaderboard(:weekly),
      "alltime" => ::Certification::Ship.leaderboard(:alltime)
    }
  end

  def logs
    authorize ::Certification::Ship, :logs?

    @status = params[:status].presence_in(%w[approved returned all]) || "all"
    @sort = params[:sort] == "oldest" ? "oldest" : "newest"
    @search = params[:search].to_s.strip
    @from = parse_date(params[:from])
    @to = parse_date(params[:to])

    scope = policy_scope(::Certification::Ship)
              .decided
              .includes(:reviewer, project: { memberships: :user })

    scope = scope.where(status: @status) unless @status == "all"
    scope = scope.where("certification_ship_reviews.decided_at >= ?", @from.beginning_of_day) if @from
    scope = scope.where("certification_ship_reviews.decided_at <= ?", @to.end_of_day) if @to
    scope = apply_search(scope) if @search.present?

    @pagy, @ships = pagy(:offset,
                         scope.order(decided_at: @sort == "newest" ? :desc : :asc),
                         limit: 25)
  end

  def show
    authorize @ship
    if params[:via] == "dashboard"
      return redirect_to admin_certification_ships_path, alert: "This project has been deleted." if @ship.project.deleted_at?
      return redirect_to project_path(@ship.project)
    end
    if internal_sw_dash_reviews_disabled? && (dash_url = ExternalDashboard::Client.certification_url(@ship.external_certification_id))
      return redirect_to dash_url, allow_other_host: true
    end
    set_milestone_context
  end

  def report_fraud
    authorize @ship

    report = ::Project::Report.new(
      project_id: @ship.project_id,
      reporter_id: current_user.id,
      reason: "Shipwrights project flag",
      details: params[:details],
      status: :pending
    )

    if report.save
      render json: { success: true, message: "Report submitted successfully" }, status: :created
    else
      errors = if report.errors.of_kind?(:reporter_id, :taken)
        [ "This project has already been reported" ]
      else
        report.errors.full_messages
      end
      render json: { success: false, errors: errors }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    render json: { success: false, errors: [ "This project has already been reported" ] }, status: :unprocessable_entity
  end

  def set_project_type
    authorize @ship
    type = params[:project_type].presence_in(Project::AVAILABLE_CATEGORIES)
    if type
      @ship.project.update!(project_type: type)
      redirect_to ship_redirect_path, notice: "Project type updated."
    else
      redirect_to ship_redirect_path, alert: "Invalid project type."
    end
  end

  # "This shouldn't be in this queue": hands the ship back to the builder to
  # confirm it belongs in the design queue instead. No verdict is recorded and
  # no bounty is earned - the reviewer is routing, not deciding.
  def flag_queue_mismatch
    authorize @ship
    if @ship.flag_queue_mismatch!(reviewer: current_user, reason: params[:reason])
      redirect_to hardware_review_next_path_for(@ship.project, "build"),
                  notice: "Sent back to the builder to confirm it needs funding first."
    else
      redirect_to ship_redirect_path, alert: "This review isn't pending, so it can't be re-routed."
    end
  end

  def set_bonus_stardust
    authorize @ship
    @ship.update!(bonus_stardust: params[:bonus_stardust].presence)
    redirect_to admin_certification_ship_path(@ship), notice: "Bonus stardust updated."
  end

  def update
    authorize @ship
    if internal_sw_dash_reviews_disabled? && @ship.external_certification_id.present?
      return redirect_to admin_certification_ships_path, alert: "Reviews are handled on the Shipwrights dashboard."
    end
    return redirect_to admin_certification_ship_path(@ship), alert: "Ship is no longer pending." unless @ship.pending?

    @ship.reviewer = current_user
    if @ship.update(ship_params)
      verb = @ship.approved? ? "Approved" : "Returned"
      count = ::Certification::Ship.reviewed_today(current_user)
      notice = "#{verb} \"#{@ship.project.title}.\" That's #{count} reviewed today. Keep going!"
      if params[:redirect_to_hardware].present?
        # Straight on to the next build review; `next` claims it, and falls back
        # to the queue when there's nothing left.
        redirect_to hardware_review_next_path_for(@ship.project, "build"), notice: notice
      else
        redirect_to admin_certification_ships_path, notice: notice
      end
    else
      if params[:redirect_to_hardware].present?
        load_hardware_review_context
        render "admin/certification/hardware_reviews/show", status: :unprocessable_entity
      else
        set_milestone_context
        render :show, status: :unprocessable_entity
      end
    end
  end

  def next
    authorize ::Certification::Ship
    return redirect_to admin_certification_ships_path, notice: "Reviews are handled on the Shipwrights dashboard." if internal_sw_dash_reviews_disabled?
    skip_ids = parse_skip_ids
    candidate = ::Certification::Ship.next_eligible(current_user, skip_ids: skip_ids)
    if candidate.nil?
      redirect_to admin_certification_ships_path, notice: "Queue is empty." and return
    end
    claimed = ::Certification::Ship.atomic_claim!(candidate.id, current_user)
    if claimed
      redirect_to admin_certification_ship_path(claimed)
    else
      new_skip = (skip_ids + [ candidate.id ]).uniq
      redirect_to next_admin_certification_ships_path(skip: new_skip.join(","))
    end
  end

  private

  # Also loaded for update so the re-rendered show page keeps the submitter
  # panel when the verdict form fails validation.
  def set_submitter_context
    @owner = @ship.owner
    @submitter_history = @owner && ::Certification::Ship.submitter_history(@owner)
  end

  def set_ship
    @ship = ::Certification::Ship.find(params[:id])
  end

  # Names the record HardwareReviewUndoable#undo reverses.
  def review_for_undo = @ship

  def set_milestone_context
    @reviews_today = ::Certification::Ship.reviewed_today(current_user)
    @current_multiplier = ::Certification::Ship.multiplier_for_milestone(@reviews_today)
    @next_milestone = ::Certification::Ship.next_milestone(@reviews_today)
  end

  def ship_redirect_path
    if params[:redirect_to_hardware].present?
      hardware_review_path_for(@ship.project)
    else
      admin_certification_ship_path(@ship)
    end
  end

  def load_hardware_review_context
    @project = @ship.project
    @funding_request = @project.latest_funding_request
    @owner = @ship.owner
    @active_review = @ship
    @active_review_type = :ship
    @reviewed_today = ::Certification::FundingRequest.reviewed_today(current_user) +
                      ::Certification::Ship.reviewed_today(current_user)
    @lapse_timelapses = Rails.cache.fetch([ "hardware_review_recordings", "lapse", @project.id ], expires_in: 1.minute) do
      LapseService.timelapses_for_project(
        hackatime_user_id: @owner&.hackatime_identity&.uid,
        project_keys: @project.hackatime_keys
      )
    end
    @lookout_recordings = Rails.cache.fetch([ "hardware_review_recordings", "lookout", @project.id ], expires_in: 1.minute) do
      LookoutService.recordings_for_project(@project)
    end
  end

  # The .app-layout wrapper reserves the sidebar gutter itself; this body class
  # zeroes the body's own sidebar margin so the two don't stack into a huge gap.
  def set_body_class
    @body_class = "app-layout-page"
  end

  def release_other_claims
    ::Certification::Ship.release_all_for(current_user) if current_user.present?
  end

  def internal_sw_dash_reviews_disabled?
    Flipper.enabled?(:disable_internal_sw_dash_reviews, current_user)
  end

  def parse_skip_ids
    params[:skip].to_s.split(",").map(&:to_i).reject(&:zero?)
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # Numeric input matches a review id or a project title; text matches title.
  def apply_search(scope)
    if @search.match?(/\A\d+\z/)
      scope.where("certification_ship_reviews.id = :id OR projects.title ILIKE :q",
                  id: @search.to_i, q: "%#{@search}%")
    else
      scope.where("projects.title ILIKE ?", "%#{@search}%")
    end
  end

  def ship_params
    params.require(:certification_ship).permit(:status, :feedback, :verdict_video)
  end
end
