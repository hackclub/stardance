class MissionSubmissionsController < ApplicationController
  before_action :set_body_class, only: [ :index, :show, :redeem ]
  before_action :set_submission, only: [ :show, :approve, :reject, :undo, :redeem ]

  def index
    authorize Mission::Submission

    scope = policy_scope(Mission::Submission).includes(:mission, ship_event: { post: [ :user, :project ] })

    if params[:status].present? && Mission::Submission.aasm.states.map(&:name).map(&:to_s).include?(params[:status])
      scope = scope.where(status: params[:status])
    end

    if params[:mission_id].present?
      scope = scope.where(mission_id: params[:mission_id])
    end

    @submissions = scope.order(created_at: :desc).limit(100)
  end

  def show
    authorize @submission
    @versions = @submission.versions.order(created_at: :asc).to_a
    whodunnit_ids = @versions.map(&:whodunnit).compact.uniq
    @whodunnit_users = User.where(id: whodunnit_ids).index_by { |u| u.id.to_s }
  end

  def approve
    authorize @submission
    Mission::Submission.transaction do
      @submission.update!(reviewed_by: current_user, reviewed_at: Time.current)
      @submission.approve!
      grant_mission_achievement_if_configured
    end
    notify_builder("submission_approved")
    redirect_to @submission, notice: "Submission approved."
  end

  def reject
    authorize @submission
    message = params[:rejection_message].to_s.strip
    return redirect_to(@submission, alert: "Provide a rejection reason.") if message.blank?

    @submission.update!(reviewed_by: current_user, reviewed_at: Time.current, rejection_message: message)
    @submission.reject!
    notify_builder("submission_rejected")
    redirect_to @submission, notice: "Submission rejected."
  end

  def undo
    authorize @submission
    @submission.update!(reviewed_by: nil, reviewed_at: nil, rejection_message: nil)
    @submission.undo!
    redirect_to @submission, notice: "Submission moved back to pending."
  end

  def redeem
    authorize @submission
    @prizes = @submission.mission.prizes.ordered.includes(:shop_item).to_a
  end

  private

  def set_body_class
    @body_class = "app-layout-page"
  end

  def set_submission
    @submission = Mission::Submission.find(params[:id])
  end


  def grant_mission_achievement_if_configured
    mission = @submission.mission
    return if mission.achievement_slug.blank?
    builder = @submission.ship_event&.post&.user
    return unless builder

    return if builder.user_achievements.exists?(achievement_slug: mission.achievement_slug)

    builder.user_achievements.create!(
      achievement_slug: mission.achievement_slug,
      earned_at: Time.current
    )
  end

  def notify_builder(template_basename)
    builder = @submission.ship_event&.post&.user
    return unless builder&.slack_id.present?

    SendSlackDmJob.perform_later(
      builder.slack_id,
      blocks_path: "notifications/missions/#{template_basename}.slack_message",
      locals: @submission.notification_locals
    )
  rescue StandardError => e
    Rails.logger.warn("MissionSubmissions notify_builder: #{e.message}")
  end
end
