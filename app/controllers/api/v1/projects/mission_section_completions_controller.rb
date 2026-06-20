class Api::V1::Projects::MissionSectionCompletionsController < Api::BaseController
  include ApiAuthenticatable

  before_action :set_project

  def index
    attachment = @project.mission_attachments.where(detached_at: nil).first
    unless attachment
      return render json: { error: "Project has no active mission", request_id: request.request_id }, status: :unprocessable_entity
    end

    completions = @project.mission_section_completions
                          .where(mission_id: attachment.mission_id)
                          .includes(:mission_step)
                          .order("mission_steps.position")

    render json: {
      mission_slug: attachment.mission.slug,
      completions: completions.map { |c|
        { mission_step_id: c.mission_step_id, title: c.mission_step.title, completed_at: c.completed_at }
      }
    }
  end

  def create
    step = Mission::Step.where(deleted_at: nil).find_by(id: params[:mission_step_id])
    return render json: { error: "Step not found", request_id: request.request_id }, status: :not_found if step.nil?

    unless @project.mission_attachments.where(mission_id: step.mission_id, detached_at: nil).exists?
      return render json: { error: "Project is not enrolled in this mission", request_id: request.request_id }, status: :unprocessable_entity
    end

    begin
      @project.mission_section_completions.find_or_create_by!(mission_step_id: step.id) do |c|
        c.mission_id   = step.mission_id
        c.completed_at = Time.current
      end
    rescue ActiveRecord::RecordNotUnique
      # concurrent POST — already completed, treat as ok
    end

    render json: { completed: true }
  end

  def destroy
    step = Mission::Step.unscoped.find_by(id: params[:id])
    return render json: { error: "Step not found", request_id: request.request_id }, status: :not_found if step.nil?

    unless @project.mission_attachments.where(mission_id: step.mission_id, detached_at: nil).exists?
      return render json: { error: "Project is not enrolled in this mission", request_id: request.request_id }, status: :unprocessable_entity
    end

    @project.mission_section_completions.where(mission_step_id: step.id).destroy_all
    render json: { completed: false }
  end

  private

  def set_project
    @project = current_api_user.projects.find(params[:project_id])
  end
end
