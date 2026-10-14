class Projects::QueueMismatchesController < ApplicationController
  before_action -> { head :not_found unless Flipper.enabled?(:hardware_flow, current_user) }
  before_action :set_project
  before_action :set_review

  # The builder agrees the submission was in the wrong queue: it is withdrawn
  # and the project switches to the stage it should have been in, ready to
  # submit to the other queue straight away.
  def update
    authorize @project, :ship?

    if @review.confirm_queue_conversion!
      track_event "queue_mismatch_confirmed",
                  { project_id: @project.id, review_type: @review.class.name }
      redirect_to project_path(@project), notice: confirmation_notice
    else
      redirect_to project_path(@project), alert: "That question has already been answered."
    end
  end

  # The builder disagrees: the submission goes straight back into the queue it
  # came from, unclaimed, so the next reviewer through picks it up.
  def destroy
    authorize @project, :ship?

    if @review.dispute_queue_mismatch!
      track_event "queue_mismatch_disputed",
                  { project_id: @project.id, review_type: @review.class.name }
      redirect_to project_path(@project),
                  notice: "Thanks! We've put it back in the review queue as it was."
    else
      redirect_to project_path(@project), alert: "That question has already been answered."
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_review
    @review = @project.review_awaiting_queue_answer
    redirect_to project_path(@project), alert: "There's nothing waiting on an answer." if @review.nil?
  end

  def confirmation_notice
    if @review.is_a?(::Certification::FundingRequest)
      "Got it, your project is in the build stage now. Ship it whenever you're ready!"
    else
      "Got it, your project is back in the design stage. Submit your design to ask for a grant."
    end
  end
end
