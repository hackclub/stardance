class Admin::ProjectsController < Admin::ApplicationController
  def index
    authorize ::Project
    @query = params[:query]
    @filter = params[:filter] || "active"

    projects = case @filter
    when "deleted"
      ::Project.unscoped.deleted
    when "all"
      ::Project.unscoped.all
    else
      ::Project.all
    end

    if @query.present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      projects = projects.where("title ILIKE ? OR description ILIKE ?", q, q)
    end

    @pagy, @projects = pagy(:offset, projects.includes(mission_attachments: :mission).order(:id))
  end

  def show
    @project = ::Project.unscoped
      .includes(:users, hackatime_projects: { user: :identities })
      .find(params[:id])
    authorize @project
  end

  def votes
    @project = ::Project.find(params[:id])
    authorize @project, :view_votes?

    @pagy, @votes = pagy(
      @project.votes.includes(:user, :events).order(created_at: :desc)
    )
  end

  def restore
    @project = ::Project.unscoped.find(params[:id])
    authorize @project

    if @project.deleted?
      @project.restore!
      redirect_to admin_project_path(@project), notice: "Project restored successfully."
    else
      redirect_to admin_project_path(@project), alert: "Project is not deleted."
    end
  end

  def delete
    @project = ::Project.unscoped.find(params[:id])
    authorize @project, :destroy?

    if @project.deleted?
      redirect_to admin_project_path(@project), alert: "Project is already deleted."
    else
      @project.soft_delete!(force: true)
      redirect_to admin_project_path(@project), notice: "Project deleted successfully."
    end
  end

  def update_ship_status
    @project = ::Project.unscoped.find(params[:id])
    authorize @project, :update?

    old_status = @project.ship_status
    new_status = params[:ship_status]

    unless ::Project.aasm.states.map { |s| s.name.to_s }.include?(new_status)
      redirect_to admin_project_path(@project), alert: "Invalid ship status."
      return
    end

    if old_status == new_status
      redirect_to admin_project_path(@project), alert: "Project is already #{new_status}."
      return
    end

    @project.update_column(:ship_status, new_status)
    sync_last_ship_event_certification(new_status)
    close_pending_ship_review(new_status)

    ::PaperTrail::Version.create!(
      item: @project,
      event: "update",
      whodunnit: current_user.id.to_s,
      object_changes: { ship_status: [ old_status, new_status ] }
    )

    redirect_to admin_project_path(@project), notice: "Ship status changed from #{old_status} to #{new_status}."
  end

  def sync_last_ship_event_certification(new_status)
    ship_event = @project.last_ship_event
    return unless ship_event

    new_cert = case new_status
    when "approved" then "approved"
    when "rejected" then "rejected"
    when "needs_changes" then "returned"
    else "pending"
    end
    return if ship_event.certification_status == new_cert
    ship_event.update!(certification_status: new_cert)
  end

  # An admin override that leaves the cert pending would keep it live in both
  # review queues and let a later dashboard decision silently overwrite the
  # forced state. update_columns on purpose: the admin already forced the
  # project/ship_event state directly, so re-driving the verdict callback
  # chain here would clobber it (e.g. downgrade a forced "rejected" to
  # "returned") and mint payout reviews as a side effect.
  def close_pending_ship_review(new_status)
    return unless %w[approved needs_changes rejected].include?(new_status)

    pending = @project.ship_reviews.find_by(status: :pending)
    return unless pending

    closed = new_status == "approved" ? :approved : :returned
    pending.update_columns(
      status: ::Certification::Ship.statuses[closed],
      decided_at: Time.current,
      internal_reason: "Closed by admin ship-status override (#{current_user.id})"
    )

    ::PaperTrail::Version.create!(
      item: pending,
      event: "update",
      whodunnit: current_user.id.to_s,
      object_changes: { status: [ "pending", closed.to_s ] }
    )
  end

  def force_state
    @project = ::Project.unscoped.find(params[:id])
    authorize @project, :update?

    state_column = ::Project.aasm.attribute_name
    old_state = @project.send(state_column)
    new_state = params[:target_state]

    unless ::Project.aasm.states.map { |s| s.name.to_s }.include?(new_state)
      redirect_to admin_project_path(@project), alert: "Invalid state."
      return
    end

    if old_state == new_state
      redirect_to admin_project_path(@project), alert: "Project is already #{new_state}."
      return
    end

    @project.update_column(state_column, new_state)
    sync_last_ship_event_certification(new_state)
    close_pending_ship_review(new_state)

    ::PaperTrail::Version.create!(
      item: @project,
      event: "update",
      whodunnit: current_user.id.to_s,
      object_changes: { state_column => [ old_state, new_state ] }
    )

    redirect_to admin_project_path(@project), notice: "State forced from #{old_state} to #{new_state}."
  end

  # Admin override of Projects::MissionsController#destroy: skips the
  # builder-facing "already shipped to this mission" guard so a mission can
  # be detached from this page regardless of ship state. detach_mission!
  # itself has no state-based validation, so this always succeeds as long as
  # a mission is currently attached.
  def detach_mission
    @project = ::Project.unscoped.find(params[:id])
    authorize @project, :detach_mission?

    attachment = @project.current_mission_attachment
    unless attachment
      redirect_to admin_project_path(@project), alert: "No mission attached."
      return
    end

    mission = attachment.mission
    restored = @project.detach_mission!

    notice = if restored
      "Detached from the #{mission.name} mission — now on #{restored.name}."
    else
      "Detached from the #{mission.name} mission."
    end
    redirect_to admin_project_path(@project), notice: notice
  end
end
