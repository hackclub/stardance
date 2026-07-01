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

    @pagy, @projects = pagy(:offset, projects.order(:id))
  end

  def show
    @project = ::Project.unscoped.find(params[:id])
    authorize @project
  end

  def votes
    @project = ::Project.find(params[:id])
    authorize @project, :show?

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

    log_admin_version("update", ship_status: [ old_status, new_status ])

    redirect_to admin_project_path(@project), notice: "Ship status changed from #{old_status} to #{new_status}."
  end

  def update_hardware_stage
    @project = ::Project.unscoped.find(params[:id])
    authorize @project, :update?

    old_stage = @project.hardware_stage
    new_stage = params[:hardware_stage].presence
    reason = params[:reason].to_s.strip

    unless ([ nil ] + ::Project::HARDWARE_STAGES).include?(new_stage)
      redirect_to admin_project_path(@project), alert: "Invalid project kind."
      return
    end

    if reason.blank?
      redirect_to admin_project_path(@project), alert: "Explain why the project kind is being changed."
      return
    end

    # Setting Software overrules the AI classifier. Without this, a stale
    # project_type == "Hardware" would keep the project out of the review queue
    # (Certification::Ship.excluding_hardware) even after the override — even
    # when the project is already Software, so this is reachable past the no-op
    # guard below.
    old_project_type = @project.project_type
    clear_classifier = new_stage.nil? && old_project_type == "Hardware"

    if old_stage == new_stage && !clear_classifier
      redirect_to admin_project_path(@project), alert: "Project kind is already #{hardware_stage_label(new_stage)}."
      return
    end

    funding_lock_bypassed = @project.has_any_funding_request?
    resolved_review_ids = []

    @project.hardware_stage = new_stage
    @project.project_type = nil if clear_classifier
    ApplicationRecord.transaction do
      ::PaperTrail.request(enabled: false) do
        @project.save!(validate: false)
      end
      # A now-hardware project's open software review is misrouted — close it so
      # it doesn't sit stale (it's already filtered out of auto-assignment).
      resolved_review_ids = resolve_open_ship_reviews!("Converted to hardware by staff; software ship review closed: #{reason}") if new_stage.present?
    end

    changes = {
      "hardware_stage" => [ old_stage, new_stage ],
      "project_kind" => [ hardware_stage_label(old_stage), hardware_stage_label(new_stage) ],
      "reason" => reason,
      "funding_lock_bypassed" => funding_lock_bypassed
    }
    changes["project_type"] = [ old_project_type, nil ] if clear_classifier
    changes["resolved_ship_review_ids"] = resolved_review_ids if resolved_review_ids.any?
    log_admin_version("admin_hardware_stage_update", changes)

    notice = if old_stage == new_stage
      "Cleared the stale Hardware classifier; project kind stays #{hardware_stage_label(new_stage)}."
    else
      "Project kind changed from #{hardware_stage_label(old_stage)} to #{hardware_stage_label(new_stage)}."
    end
    redirect_to admin_project_path(@project), notice: notice
  end

  # Soft-resets the project's most recent ship back to an un-shipped draft so the
  # owner can fix it and re-ship. NOTHING IS DELETED — the ship event, its
  # review, votes, YSWS links and ledger entries are all preserved for history
  # and audit. We only flip status columns: the project back to draft, the ship
  # event's certification back to pending (so it no longer blocks re-shipping),
  # and clear shipped_at so it reads as un-shipped. Refuses to reset a paid-out
  # ship.
  def reset_latest_ship
    @project = ::Project.unscoped.find(params[:id])
    authorize @project, :update?

    reason = params[:reason].to_s.strip
    ship_event = @project.last_ship_event

    if ship_event.nil?
      redirect_to admin_project_path(@project), alert: "This project has no ship to reset."
      return
    end

    if reason.blank?
      redirect_to admin_project_path(@project), alert: "Explain why the latest ship is being reset."
      return
    end

    if ship_event.payout.present?
      redirect_to admin_project_path(@project),
                  alert: "Can't reset a ship that has already paid out. Resolve the payout first."
      return
    end

    old_status = @project.ship_status
    old_ship_status = ship_event.certification_status
    resolved_review_ids = []

    ApplicationRecord.transaction do
      ship_event.update_columns(certification_status: "pending")
      # Don't leave a pending review behind for a project that's no longer
      # submitted — it would sit stale in the queue / get picked by a reviewer.
      resolved_review_ids = resolve_open_ship_reviews!("Latest ship reset to draft by staff: #{reason}")
      @project.update_columns(ship_status: "draft", shipped_at: nil)
    end

    changes = {
      "ship_status" => [ old_status, "draft" ],
      "ship_event_id" => ship_event.id,
      "certification_status" => [ old_ship_status, "pending" ],
      "reason" => reason
    }
    changes["resolved_ship_review_ids"] = resolved_review_ids if resolved_review_ids.any?
    log_admin_version("admin_reset_latest_ship", changes)

    redirect_to admin_project_path(@project),
                notice: "Reset the latest ship back to draft. Nothing was deleted — the ship and its review are preserved."
  end

  def sync_last_ship_event_certification(new_status)
    ship_event = @project.last_ship_event
    return unless ship_event

    new_cert = case new_status
    when "approved" then "approved"
    when "rejected" then "rejected"
    else "pending"
    end
    return if ship_event.certification_status == new_cert
    ship_event.update!(certification_status: new_cert)
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

    log_admin_version("update", state_column => [ old_state, new_state ])

    redirect_to admin_project_path(@project), notice: "State forced from #{old_state} to #{new_state}."
  end

  private

  # Takes any still-open (pending) ship review out of the reviewer queue when a
  # staff action makes it moot, so a review is never left stale or routed to the
  # wrong reviewer. Non-destructive — the review row is kept, just marked
  # returned, unclaimed and stamped with an internal note. Uses update_all to
  # skip the verdict / notify-owner / stardust callbacks. Returns affected ids.
  def resolve_open_ship_reviews!(note)
    reviews = @project.ship_reviews.where(status: :pending)
    ids = reviews.pluck(:id)
    return ids if ids.empty?

    reviews.update_all(
      status: ::Certification::Ship.statuses[:returned],
      reviewer_id: nil,
      claimed_at: nil,
      claim_expires_at: nil,
      decided_at: Time.current,
      internal_reason: note,
      updated_at: Time.current
    )
    ids
  end

  # Records a staff action against @project in the PaperTrail audit log.
  def log_admin_version(event, object_changes)
    ::PaperTrail::Version.create!(
      item: @project,
      event: event,
      whodunnit: current_user.id.to_s,
      object_changes: object_changes
    )
  end

  def hardware_stage_label(stage)
    case stage
    when "design" then "Hardware - design"
    when "build" then "Hardware - build"
    else "Software"
    end
  end
end
