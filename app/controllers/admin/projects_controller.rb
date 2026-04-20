class Admin::ProjectsController < Admin::ApplicationController
  def index
    authorize :admin, :manage_projects?
    @query = params[:query]
    @filter = params[:filter] || "active"

    projects = case @filter
    when "deleted"
      Project.unscoped.deleted
    when "all"
      Project.unscoped.all
    else
      Project.all
    end

    if @query.present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      projects = projects.where("title ILIKE ? OR description ILIKE ?", q, q)
    end

    @pagy, @projects = pagy(:offset, projects.order(:id))
  end

  def show
    authorize :admin, :manage_projects?
    @project = Project.unscoped.find(params[:id])
  end

  def votes
    authorize :admin, :manage_projects?
    @project = Project.find(params[:id])

    @pagy, @votes = pagy(
      @project.votes.includes(:user).order(created_at: :desc)
    )
  end

  def restore
    authorize :admin, :manage_projects?
    @project = Project.unscoped.find(params[:id])

    if @project.deleted?
      @project.restore!
      redirect_to admin_project_path(@project), notice: "Project restored successfully."
    else
      redirect_to admin_project_path(@project), alert: "Project is not deleted."
    end
  end

  def delete
    authorize :admin, :manage_projects?
    @project = Project.unscoped.find(params[:id])

    if @project.deleted?
      redirect_to admin_project_path(@project), alert: "Project is already deleted."
    else
      @project.soft_delete!(force: true)
      redirect_to admin_project_path(@project), notice: "Project deleted successfully."
    end
  end

  def update_ship_status
    authorize :admin, :manage_projects?
    @project = Project.unscoped.find(params[:id])

    old_status = @project.ship_status
    new_status = params[:ship_status]

    unless Project.aasm.states.map { |s| s.name.to_s }.include?(new_status)
      redirect_to admin_project_path(@project), alert: "Invalid ship status."
      return
    end

    if old_status == new_status
      redirect_to admin_project_path(@project), alert: "Project is already #{new_status}."
      return
    end

    @project.update_column(:ship_status, new_status)

    PaperTrail::Version.create!(
      item: @project,
      event: "update",
      whodunnit: current_user.id.to_s,
      object_changes: { ship_status: [ old_status, new_status ] }
    )

    redirect_to admin_project_path(@project), notice: "Ship status changed from #{old_status} to #{new_status}."
  end

  def force_state
    authorize :admin, :manage_projects?
    @project = Project.unscoped.find(params[:id])

    state_column = Project.aasm.attribute_name
    old_state = @project.send(state_column)
    new_state = params[:target_state]

    unless Project.aasm.states.map { |s| s.name.to_s }.include?(new_state)
      redirect_to admin_project_path(@project), alert: "Invalid state."
      return
    end

    if old_state == new_state
      redirect_to admin_project_path(@project), alert: "Project is already #{new_state}."
      return
    end

    @project.update_column(state_column, new_state)

    PaperTrail::Version.create!(
      item: @project,
      event: "update",
      whodunnit: current_user.id.to_s,
      object_changes: { state_column => [ old_state, new_state ] }
    )

    redirect_to admin_project_path(@project), notice: "State forced from #{old_state} to #{new_state}."
  end
end
