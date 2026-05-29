class Projects::MissionsController < ApplicationController
  before_action :set_project

  def create
    authorize @project, :update?
    mission = Mission.available.find_by!(slug: params[:mission_slug])

    @project.mission_attachments.create!(mission: mission, attached_at: Time.current)

    redirect_to project_path(@project), notice: "Attached to the #{mission.name} mission."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to project_path(@project), alert: e.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotFound
    redirect_to project_path(@project), alert: "Mission not found."
  end

  def destroy
    authorize @project, :update?
    attachment = @project.mission_attachments.where(detached_at: nil).order(attached_at: :desc).first
    return redirect_to(project_path(@project), alert: "No mission attached.") unless attachment

    mission = attachment.mission
    attachment.detach!

    redirect_to project_path(@project), notice: "Detached from the #{mission.name} mission."
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
