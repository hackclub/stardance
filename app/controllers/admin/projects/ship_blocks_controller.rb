class Admin::Projects::ShipBlocksController < Admin::ApplicationController
  before_action :set_project

  def create
    authorize @project, :block_shipping?

    reason = params[:reason].to_s.gsub("\r\n", "\n").strip
    if reason.blank?
      redirect_to admin_project_path(@project), alert: "A reason is required to block a project from shipping."
    elsif reason.length > Project::ShipBlock::REASON_MAX_LENGTH
      redirect_to admin_project_path(@project), alert: "The reason can be at most #{Project::ShipBlock::REASON_MAX_LENGTH} characters."
    elsif @project.block_shipping!(by: current_user, reason: reason)
      redirect_to admin_project_path(@project), notice: "Project blocked from shipping. #{owner_notification_notice}"
    else
      redirect_to admin_project_path(@project), alert: "Project is already blocked from shipping."
    end
  end

  def destroy
    authorize @project, :unblock_shipping?

    if @project.unblock_shipping!(by: current_user)
      redirect_to admin_project_path(@project), notice: "Project unblocked. #{owner_notification_notice}"
    else
      redirect_to admin_project_path(@project), alert: "Project is not blocked from shipping."
    end
  end

  private

  def set_project
    @project = ::Project.unscoped.find(params[:project_id])
  end

  def owner_notification_notice
    if @project.ship_block_notifies_owner?
      "The owner has been notified on Slack."
    elsif @project.deleted?
      "The owner wasn't notified, because the project is deleted."
    else
      "The owner wasn't notified, because they have no Slack account linked."
    end
  end
end
