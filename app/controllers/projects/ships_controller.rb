class Projects::ShipsController < ApplicationController
  before_action :set_project
  before_action :require_shippable, only: [ :create ]

  def create
    authorize @project, :ship?
    # Everything posts from the modal on the project show page.
    mission_payout_path = params[:mission_payout_path]
    submission_guide_ack = params[:mission_submission_guide_acknowledged].to_s == "1"

    if mission_submission_guide_ack_required? && !submission_guide_ack
      redirect_to project_path(@project),
                  alert: "Read and acknowledge the mission submission guide before shipping." and return
    end

    unless @project.readme_is_raw_github_url?
      flash.now[:warning] = "Your README link doesn't appear to be a raw GitHub URL. Are you sure you're using another Git Hosting provider?"
    end

    reship = has_previous_approved_ships?
    probe_result = reship ? ProjectUrlProbeService.new(@project).call : nil

    @project.with_lock do
      @project.submit_for_review!
      ship_event = Post::ShipEvent.new(body: params[:ship_update].to_s.strip)
      ship_event.uploading_attachments = params.dig(:ship_event, :attachments).present?
      ship_event.save!
      if ship_event.uploading_attachments
        ship_event.attachments.attach(params[:ship_event][:attachments])
        raise ActiveRecord::RecordInvalid, ship_event unless ship_event.valid?
      end
      @post = @project.posts.create!(user: current_user, postable: ship_event)
      maybe_create_mission_submission(ship_event, mission_payout_path, submission_guide_ack)

      # First Ship: Always create ship certification for manual review    ----------- Ask @AVD if you want to change this! - May need to notify teams of any changes!
      # Reships: If links alive - approves project, create a 'reship' YSWS review, if links dead - Creates ship cert for manual review
      if !reship
        @project.ship_reviews.create!(status: :pending)
      elsif probe_result.ok?
        @project.approve! if @project.may_approve?
        @post.postable.update!(certification_status: "approved")
        create_ysws_review(ship_event)
      else
        @project.ship_reviews.create!(
          status: :returned,
          feedback: "Automated URL check failed: #{probe_result.failures.join('; ')}. Please make sure your links are online and public, then re-ship!"
        )
      end
    end

    track_event "project_shipped", { project_id: @project.id, reship: reship }

    if !reship
      redirect_to project_path(@project, just_shipped: 1), notice: "Congratulations! Your project has been submitted for review! While you wait, rate other projects at the voting booth."
    elsif probe_result.ok?
      redirect_to project_path(@project, just_shipped: 1), notice: "Ship submitted! Your project is now out for voting. Rate other projects to help yours get noticed too."
    else
      redirect_to project_path(@project), notice: "We couldn't reach your links. Make sure they're online and public, then submit again!"
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: project_path(@project), alert: e.record.errors.full_messages.to_sentence
  end

  private
    def set_project
      @project = Project.find(params[:project_id])
    end

    def require_shippable
      return if @project.shippable?
      redirect_to project_path(@project), alert: "Finish the remaining requirements before shipping."
    end

    def mission_submission_guide_ack_required?
      mission = @project.current_mission
      return false if mission.nil? || @project.shipped_to_mission?(mission)
      mission.submission_guide.present?
    end

    def maybe_create_mission_submission(ship_event, payout_path_param, submission_guide_acknowledged = false)
      attachment = @project.current_mission_attachment
      return unless attachment

      mission = attachment.mission
      return if @project.shipped_to_mission?(mission)
      payout_path = resolve_payout_path(mission, payout_path_param)
      ack_time = (submission_guide_acknowledged && mission.submission_guide.present?) ? Time.current : nil

      Mission::Submission.create!(
        ship_event: ship_event,
        mission: mission,
        payout_path: payout_path,
        submission_guide_acknowledged_at: ack_time
      )
    end

    def resolve_payout_path(mission, payout_path_param)
      if mission.fixed_stardust_payout&.positive? && !current_user.completed_mission_ids.include?(mission.id)
        return "static_prize"
      end
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

    def create_ysws_review(ship_event)
      Certification::YswsReviewCreator.new(
        ship_event: ship_event,
        user: current_user,
        project: @project
      ).call
    end

    def has_previous_approved_ships?(excluding_ship_event: nil) # this could be scoped. note that post:ship_event is source of truth for ship events, as ship certifications aren't made for each ship event
      if excluding_ship_event
        @project.posts
          .joins("INNER JOIN post_ship_events ON posts.postable_id = post_ship_events.id AND posts.postable_type = 'Post::ShipEvent'")
          .where(post_ship_events: { certification_status: "approved" })
          .where.not(post_ship_events: { id: excluding_ship_event.id })
          .exists?
      else
        @project.posts
          .joins("INNER JOIN post_ship_events ON posts.postable_id = post_ship_events.id AND posts.postable_type = 'Post::ShipEvent'")
          .where(post_ship_events: { certification_status: "approved" })
          .exists?
      end
    end
end
