class Admin::Certification::ShipsController < Admin::Certification::ApplicationController
  before_action :release_other_claims, only: [ :next ]
  before_action :set_ship, only: [ :show, :update ]
  before_action :set_body_class, only: [ :index, :show, :update ]

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
                         scope.includes(:reviewer, project: { memberships: :user })
                              .order(created_at: @sort == "newest" ? :desc : :asc),
                         limit: 25)

    @own_project_ids = current_user.memberships.pluck(:project_id).to_set

    @stats = ::Certification::Ship.dashboard_stats
    @lb_period = params[:lb].presence_in(%w[daily weekly alltime]) || "daily"
    @leaderboards = {
      "daily" => ::Certification::Ship.leaderboard(:daily),
      "weekly" => ::Certification::Ship.leaderboard(:weekly),
      "alltime" => ::Certification::Ship.leaderboard(:alltime)
    }
  end

  def show
    authorize @ship
    @reviewed_today = ::Certification::Ship.reviewed_today(current_user)
  end

  def update
    authorize @ship
    if @ship.update(ship_params)
      verb = @ship.approved? ? "Approved" : "Returned"
      count = ::Certification::Ship.reviewed_today(current_user)
      redirect_to next_admin_certification_ships_path,
                  notice: "#{verb} “#{@ship.project.title}.” That's #{count} reviewed today. Keep going!"
    else
      render :show, status: :unprocessable_entity
    end
  end

  def next
    authorize ::Certification::Ship
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

  def set_ship
    @ship = ::Certification::Ship.find(params[:id])
  end

  # The .app-layout wrapper reserves the sidebar gutter itself; this body class
  # zeroes the body's own sidebar margin so the two don't stack into a huge gap.
  def set_body_class
    @body_class = "app-layout-page"
  end

  def release_other_claims
    ::Certification::Ship.release_all_for(current_user) if current_user.present?
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
