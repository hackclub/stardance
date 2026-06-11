class Projects::MagicController < ApplicationController
  before_action :set_project

  def create
    magic = Project::Magic.new(@project)
    authorize magic

    if magic.grant(current_user)
      redirect_back_or_to project_path(@project), notice: "Project marked as Super Star."
    else
      redirect_back_or_to project_path(@project), alert: magic.errors.full_messages.to_sentence
    end
  end

  def destroy
    magic = Project::Magic.new(@project)
    authorize magic

    if magic.revoke(current_user)
      redirect_back_or_to project_path(@project), notice: "Project unmarked as Super Star."
    else
      redirect_back_or_to project_path(@project), alert: magic.errors.full_messages.to_sentence
    end
  end

  private
    def set_project
      @project = Project.find(params[:project_id])
    end
end
