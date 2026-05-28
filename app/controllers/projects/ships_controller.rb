class Projects::ShipsController < ApplicationController
  before_action :set_project
  before_action :setup_chrome,    only: [ :new, :info, :review_step, :compose, :create ]
  before_action :require_shippable, only: [ :review_step, :compose ]

  # Step 0 — "what is a ship" refresher (video only). Entry point.
  def new
    authorize @project, :ship?
    @step = 0
  end

  # Step 1 — project info form. Available regardless of shippable? state,
  # since this is the screen where you fix unmet requirements.
  def info
    authorize @project, :ship?
    @step = 1
    @project_times = current_user.try_sync_hackatime_data!&.dig(:projects) || {}
  end

  # Step 2 — review instructions form. Requires the project to be shippable
  # (handled by the before_action).
  def review_step
    authorize @project, :ship?
    @step = 2
  end

  # Step 3 — ship composer. Same shippable gate as step 2.
  def compose
    authorize @project, :ship?
    @step = 3
    @last_ship = @project.last_ship_event
  end

  def create
    # authorize @project, :ship?
    wizard = session.delete(:ship_wizard) || {}
    review_instructions = (wizard["review_instructions"].presence || params[:review_instructions]).to_s.strip.presence
    mission_payout_path = wizard["mission_payout_path"].presence || params[:mission_payout_path]

    unless @project.readme_is_raw_github_url?
      flash.now[:warning] = "Your README link doesn't appear to be a raw GitHub URL. We require raw README files (from raw.githubusercontent.com) for proper display and consistency. Please update your README URL."
    end

    @project.with_lock do
      @project.submit_for_review!
      ship_event = Post::ShipEvent.create!(
        body: params[:ship_update].to_s.strip,
        review_instructions: review_instructions
      )
      @post = @project.posts.create!(user: current_user, postable: ship_event)
      maybe_create_mission_submission(ship_event, mission_payout_path)
    end

    if initial_ship?
      redirect_to project_path(@project), notice: "Congratulations! Your project has been submitted for review!"
    else
      @post.postable.update!(certification_status: "approved")
      redirect_to project_path(@project), notice: "Ship submitted! Your project is now out for voting."
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: new_project_ships_path(@project), alert: e.record.errors.full_messages.to_sentence
  end

  private
    def set_project
      @project = Project.find(params[:project_id])
    end

    # Shared chrome state for every wizard step: hide the global sidebar and
    # apply the ship-page body class so the layout knows we're in the wizard.
    def setup_chrome
      @hide_sidebar = true
      @body_class = "ship-page"
    end

    # Steps 2 and 3 can only be reached once the project meets every shipping
    # requirement. If a user lands on those URLs early (typed-in URL, stale
    # bookmark, mid-flow regression after editing project info), bounce them
    # back to the info step *with a reason* — silent redirects look like the
    # form just didn't submit.
    def require_shippable
      return if @project.shippable?

      blockers = @project.ship_blocking_errors
      flash[:alert] = if blockers.any?
                        "Can't continue yet — #{blockers.to_sentence(last_word_connector: ", and ")}."
      else
                        "Your project isn't ready to ship yet."
      end
      redirect_to info_project_ships_path(@project)
    end

    def initial_ship?
      @project.posts.where(postable_type: "Post::ShipEvent").one?
    end

    def maybe_create_mission_submission(ship_event, payout_path_param)
      return unless Flipper.enabled?(:missions, current_user)
      attachment = @project.current_mission_attachment
      return unless attachment

      mission = attachment.mission
      payout_path = resolve_payout_path(mission, payout_path_param)

      Mission::Submission.create!(
        ship_event: ship_event,
        mission: mission,
        payout_path: payout_path,
        status: "awaiting_certification"
      )
    end

    def resolve_payout_path(mission, payout_path_param)
      return "voting" unless mission.has_prizes?
      return "voting" if user_redeemed_prize_for?(mission)
      payout_path_param.to_s == "voting" ? "voting" : "static_prize"
    end

    def user_redeemed_prize_for?(mission)
      Mission::Submission
        .where(mission_id: mission.id)
        .joins(ship_event: { post: :user })
        .where(users: { id: current_user.id })
        .where.not(shop_order_id: nil)
        .exists?
    end
end
