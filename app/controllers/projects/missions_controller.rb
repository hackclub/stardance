class Projects::MissionsController < ApplicationController
  before_action :set_project

  def create
    authorize @project, :update?
    mission = Mission.available.find_by!(slug: params[:mission_slug])

    unless mission.prerequisites_met_by?(current_user)
      unmet = mission.unmet_prerequisites_for(current_user).map(&:name).to_sentence
      redirect_to project_path(@project), alert: "Complete #{unmet} first to unlock this mission." and return
    end

    @project.attach_mission!(mission)

    redirect_to project_path(@project), notice: "Attached to the #{mission.name} mission."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to project_path(@project), alert: e.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    redirect_to project_path(@project), alert: "Detach the current mission before attaching another."
  rescue ActiveRecord::RecordNotFound
    redirect_to project_path(@project), alert: "Mission not found."
  end

  def destroy
    authorize @project, :update?
    attachment = @project.current_mission_attachment
    return redirect_to(project_path(@project), alert: "No mission attached.") unless attachment

    mission = attachment.mission
    if @project.shipped_to_mission?(mission)
      return redirect_to(project_path(@project), alert: "This project already shipped to #{mission.name}, so that mission is locked in.")
    end

    restored = @project.detach_mission!

    notice = if restored
      "Detached from the #{mission.name} mission — back on #{restored.name}."
    else
      "Detached from the #{mission.name} mission."
    end
    redirect_to project_path(@project), notice: notice
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
