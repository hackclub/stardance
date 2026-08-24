# frozen_string_literal: true

# The global hardware review queue: design funding + build certification for
# hardware projects that are NOT attached to a hardware mission. Mission-attached
# hardware is reviewed by that mission's own team (Admin::Missions::HardwareReviews).
# Mutations still go through the funding/ship endpoints so PaperTrail stays attached.
class Admin::Certification::HardwareReviewsController < Admin::Certification::ApplicationController
  include HardwareReviewQueue

  before_action -> { head :not_found unless Flipper.enabled?(:hardware_flow, current_user) }
  before_action :set_project, only: [ :show, :flag_for_fraud ]
  before_action -> { head :not_found unless @project.hardware? }, only: [ :show, :flag_for_fraud ]

  # GET /admin/certification/hardware - kept so older links land somewhere sensible.
  def index
    authorize_hardware_queue
    # Only the queue's own filters carry over; splatting raw query params would
    # let reserved url_for keys (host, script_name, ...) retarget the redirect.
    redirect_to design_admin_certification_hardware_reviews_path(
      params.permit(:status, :sort, :search, :from, :to, :lb).to_h.compact_blank
    )
  end

  private

  # Hardware projects not attached to a hardware mission.
  def reviewable_projects
    Project.hardware.without_hardware_mission
  end

  def authorize_hardware_queue
    authorize Project, policy_class: Admin::Certification::HardwareReviewPolicy
  end

  def authorize_hardware_review(project)
    authorize project, policy_class: Admin::Certification::HardwareReviewPolicy
  end

  def set_project
    @project = Project.find(params[:project_id])
  end
end
