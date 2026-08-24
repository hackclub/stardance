class Admin::Certification::FundingRequestsController < Admin::Certification::ApplicationController
  include HardwareReviewUndoable

  before_action -> { head :not_found unless Flipper.enabled?(:hardware_flow, current_user) }
  before_action :set_funding_request
  before_action :set_body_class

  def update
    authorize @funding_request
    @funding_request.assign_attributes(funding_request_params)
    attach_feedback_images
    if @funding_request.save
      count = ::Certification::FundingRequest.reviewed_today(current_user)
      notice = "#{verdict_sentence} That's #{count} reviewed today. Keep going!"
      # Straight on to the next design review; `next` claims it, and falls back
      # to the queue when there's nothing left.
      redirect_to hardware_review_next_path_for(@funding_request.project, "design"), notice: notice
    else
      load_hardware_review_context
      render "admin/certification/hardware_reviews/show", status: :unprocessable_entity
    end
  end

  # "This shouldn't be in this queue": hands the request back to the builder to
  # confirm they've already finished building. No verdict is recorded and no
  # bounty is earned - the reviewer is routing, not deciding.
  def flag_queue_mismatch
    authorize @funding_request
    if @funding_request.flag_queue_mismatch!(reviewer: current_user, reason: params[:reason])
      redirect_to hardware_review_next_path_for(@funding_request.project, "design"),
                  notice: "Sent back to the builder to confirm the build is already done."
    else
      redirect_to hardware_review_path_for(@funding_request.project),
                  alert: "This review isn't pending, so it can't be re-routed."
    end
  end

  private

  # Names the verdict back to the reviewer, since "approved" now covers a grant,
  # a kit, and no funding at all.
  def verdict_sentence
    title = @funding_request.project.title
    if !@funding_request.approved?
      "Returned funding for “#{title}.”"
    elsif @funding_request.issues_grant?
      "Approved funding for “#{title}.”"
    elsif @funding_request.awards_design_kit?
      "Approved “#{title}” and sent the kit."
    elsif @funding_request.kit_mission?
      "Approved “#{title}” with no kit."
    else
      "Approved “#{title}” with no grant."
    end
  end

  def set_funding_request
    @funding_request = ::Certification::FundingRequest.find(params[:id])
  end

  # Names the record HardwareReviewUndoable#undo reverses.
  def review_for_undo = @funding_request

  # Both fetches below fan out to live HTTP (per Hackatime key / Lookout session)
  # on every render, including the re-render after a failed verdict submit. The
  # provider URLs only expire after ~1h, so a short cache keyed by project kills
  # the repeat fan-out without meaningfully staling them.
  RECORDINGS_CACHE_TTL = 1.minute

  # Lapse timelapses the builder recorded for *this* project, joined via the
  # project's Hackatime keys and the submitter's Hackatime id so reviewers see
  # the videos tied to the submission rather than the builder's whole library.
  # Returns [] when the submitter has no Hackatime link or the project has no
  # linked Hackatime keys.
  def lapse_timelapses_for_review
    Rails.cache.fetch(recordings_cache_key("lapse"), expires_in: RECORDINGS_CACHE_TTL) do
      LapseService.timelapses_for_project(
        hackatime_user_id: @funding_request.owner&.hackatime_identity&.uid,
        project_keys: @funding_request.project.hackatime_keys
      )
    end
  end

  # The project's finished Lookout screen recordings, refreshed live (Lookout's
  # stored video URLs expire). Returns [] when the project has none.
  def lookout_recordings_for_review
    Rails.cache.fetch(recordings_cache_key("lookout"), expires_in: RECORDINGS_CACHE_TTL) do
      LookoutService.recordings_for_project(@funding_request.project)
    end
  end

  def recordings_cache_key(source)
    [ "funding_review_recordings", source, @funding_request.project_id ]
  end

  # The .app-layout wrapper reserves the sidebar gutter itself; this body class
  # zeroes the body's own sidebar margin so the two don't stack into a huge gap.
  def set_body_class
    @body_class = "app-layout-page"
  end

  def load_hardware_review_context
    @project = @funding_request.project
    @ship = @project.latest_ship_review
    @owner = @project.memberships.owner.first&.user
    @active_review = @funding_request
    @active_review_type = :funding
    @reviewed_today = ::Certification::FundingRequest.reviewed_today(current_user) +
                      ::Certification::Ship.reviewed_today(current_user)
    @lapse_timelapses = lapse_timelapses_for_review
    @lookout_recordings = lookout_recordings_for_review
  end

  def funding_request_params
    params.require(:certification_funding_request).permit(:verdict, :feedback, :approved_amount_dollars)
  end

  # Reviewer-attached feedback photos. Mirrors ships_controller's attach guard:
  # only touch the association when files are actually present, so submitting a
  # verdict without picking any images leaves the request's images untouched.
  def attach_feedback_images
    images = params.dig(:certification_funding_request, :feedback_images)&.reject(&:blank?)
    @funding_request.feedback_images.attach(images) if images.present?
  end
end
