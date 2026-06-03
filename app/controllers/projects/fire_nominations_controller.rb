class Projects::FireNominationsController < ApplicationController
  before_action :set_project

  def create
    magic = Project::Magic.new(@project)
    authorize magic, :nominate?

    if magic.nominate(current_user)
      redirect_to project_path(@project), notice: "Project nominated for Super Star."
    else
      redirect_to project_path(@project), alert: magic.errors.full_messages.to_sentence
    end
  end

  def destroy
    magic = Project::Magic.new(@project)
    authorize magic, :withdraw_nomination?

    if magic.withdraw_nomination(current_user)
      redirect_to project_path(@project), notice: "Nomination withdrawn."
    else
      redirect_to project_path(@project), alert: magic.errors.full_messages.to_sentence
    end
  end

  private
    def set_project
      @project = Project.find(params[:project_id])
    end
end
