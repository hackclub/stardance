class Projects::MissionSectionCompletionsController < ApplicationController
  before_action :set_project

  def create
    authorize @project, :update?

    step = Mission::Step.where(deleted_at: nil).find_by(id: params[:mission_step_id])
    return head :unprocessable_entity if step.nil?

    # Gate INSERTs on an active attachment so update? holders can't write
    # completions for missions this project isn't enrolled in.
    unless @project.mission_attachments.where(mission_id: step.mission_id, detached_at: nil).exists?
      return head :unprocessable_entity
    end

    begin
      @project.mission_section_completions.find_or_create_by!(mission_step_id: step.id) do |c|
        c.mission_id   = step.mission_id
        c.completed_at = Time.current
      end
    rescue ActiveRecord::RecordNotUnique
      # concurrent POST won the unique index — already completed, treat as ok
    end

    render json: { completed: true }
  end

  def destroy
    authorize @project, :update?

    # Unscoped on destroy so users can always clear stale completions even if
    # the step was soft-deleted under them.
    step = Mission::Step.unscoped.find_by(id: params[:mission_step_id])
    return head :unprocessable_entity if step.nil?

    # Same gate as create: once the attachment is detached (e.g. the project
    # moved on to a follow-up mission), completions are a historical record.
    unless @project.mission_attachments.where(mission_id: step.mission_id, detached_at: nil).exists?
      return head :unprocessable_entity
    end

    @project.mission_section_completions.where(mission_step_id: step.id).destroy_all

    render json: { completed: false }
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
