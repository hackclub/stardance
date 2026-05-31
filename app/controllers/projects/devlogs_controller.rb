class Projects::DevlogsController < ApplicationController
  TEST_TIME_SECONDS = 15.minutes.to_i

  before_action :set_project
  before_action :set_devlog, only: %i[show edit update destroy versions]
  before_action :require_hackatime_project, only: %i[create]
  before_action :sync_hackatime_projects, only: %i[create]

  def show
    authorize @devlog
    @body_class = "app-layout-page"
    @post = @project.posts.visible_to(current_user).find_by!(postable: @devlog)
    @comments = @devlog.comments.includes(:user).order(created_at: :asc)
  end

  def create
    authorize @project, :create_devlog?

    current_user.with_advisory_lock("devlog_create", timeout_seconds: 10) do
      load_preview_time
      return redirect_to project_path(@project), alert: "Could not calculate your coding time. Please try again." unless @preview_time.present?

      @devlog = Post::Devlog.new(devlog_params)
      @devlog.duration_seconds = @preview_seconds
      @devlog.hackatime_projects_key_snapshot = test_time_granted? ? "test" : @project.hackatime_keys.join(",")

      if @devlog.save
        Post.create!(project: @project, user: current_user, postable: @devlog)
        session.delete(test_time_session_key) if test_time_granted?
        flash[:notice] = "Devlog created successfully"

        return redirect_to project_path(@project)
      else
        redirect_back fallback_location: home_path(project_id: @project.id),
                      alert: @devlog.errors.full_messages.to_sentence
      end
    end
  end

  def preview_time
    authorize @project, :create_devlog?
    load_preview_time
    respond_to do |format|
      format.html { render partial: "projects/devlogs/preview_time", locals: { preview_time: @preview_time, preview_seconds: @preview_seconds } }
      format.json { render json: { preview_time: @preview_time } }
    end
  end

  def edit
    authorize @devlog
  end

  def update
    authorize @devlog
    previous_body = @devlog.body

    # Remove selected attachments first
    if params[:remove_attachment_ids].present?
      attachments_to_remove = @devlog.attachments.where(id: params[:remove_attachment_ids])
      remaining_count = @devlog.attachments.count - attachments_to_remove.count
      new_attachments_count = update_devlog_params[:attachments]&.reject(&:blank?).count || 0

      if remaining_count + new_attachments_count < 1
        flash.now[:alert] = "Your devlog must have at least one attachment."
        return render :edit, status: :unprocessable_entity
      end

      attachments_to_remove.each(&:purge_later)
    end

    # Extract new attachments to append separately (don't replace existing)
    new_attachments = update_devlog_params[:attachments]
    body_params = update_devlog_params.except(:attachments)

    @devlog.uploading_attachments = new_attachments.present?

    if @devlog.update(body_params)
      # Append new attachments instead of replacing
      if new_attachments.present?
        @devlog.attachments.attach(new_attachments)
      end

      # Create version history if body changed
      if previous_body != @devlog.body
        @devlog.create_version!(user: current_user, previous_body: previous_body)
      end

      redirect_to project_path(@project), notice: "Devlog updated successfully"
    else
      flash.now[:alert] = @devlog.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @devlog
    force = params[:force] == "true" && policy(@devlog).force_destroy?
    project_shipped = @project.shipped?

    if project_shipped && !force
      flash[:alert] = "Cannot delete a devlog from a shipped project"
      redirect_to project_path(@project) and return
    end

    if force && project_shipped
      PaperTrail::Version.create!(
        item_type: "Post::Devlog",
        item_id: @devlog.id,
        event: "force_delete",
        whodunnit: current_user.id,
        object_changes: {
          deleted_at: [ nil, Time.current ],
          project_id: @project.id,
          project_shipped_at: @project.shipped_at,
          reason: "Admin/Fraud override of ship protection",
          deleted_by: current_user.id
        }.to_yaml
      )
    end

    @devlog.soft_delete!
    redirect_to project_path(@project), notice: "Devlog deleted successfully"
  end

  def versions
    authorize @devlog
    @versions = @devlog.versions.order(version_number: :desc)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_devlog
    @devlog = @project.posts
                      .where(postable_type: "Post::Devlog")
                      .find_by!(postable_id: params[:id])
                      .postable
  end

  def require_hackatime_project
    return if test_time_granted?

    unless @project.hackatime_keys.present?
      redirect_to project_path(@project), alert: "You must link at least one Hackatime project before posting a devlog" and return
    end
  end

  def sync_hackatime_projects
    return if test_time_granted?

    owner = @project.memberships.owner.first&.user
    return unless owner

    owner.try_sync_hackatime_data!
    @project.reload
  end

  def devlog_params
    params.require(:post_devlog).permit(:body, attachments: [])
  end

  def update_devlog_params
    params.require(:post_devlog).permit(:body, attachments: [])
  end

  def load_preview_time
    @preview_seconds = 0
    @project.reload
    hackatime_keys = @project.hackatime_keys

    Rails.logger.info "DevlogsController#load_preview_time: project=#{@project.id}, hackatime_keys=#{hackatime_keys.inspect}"

    return apply_test_time_preview if test_time_granted? && hackatime_keys.blank?
    return @preview_time = nil unless hackatime_keys.present?

    # Pull from the same source the project show page uses (fetch_stats via
    # try_sync_hackatime_data!) so the composer preview and the ship warning
    # modal don't disagree by a few minutes from hitting different Hackatime
    # API paths.
    result = current_user.try_sync_hackatime_data!
    return apply_test_time_preview if test_time_granted? && !result
    return @preview_time = nil unless result

    project_times = result[:projects] || {}
    total_seconds = hackatime_keys.sum { |k| project_times[k].to_i }

    @preview_seconds = [ total_seconds - @project.duration_seconds, 0 ].max
    apply_test_time_preview if test_time_granted? && @preview_seconds < TEST_TIME_SECONDS
    @preview_time ||= format_preview_time(@preview_seconds)
  rescue => e
    Rails.logger.error "Failed to load preview time: #{e.message}"
    if test_time_granted?
      apply_test_time_preview
    else
      @preview_time = nil
    end
  end

  def apply_test_time_preview
    @preview_seconds = [ @preview_seconds.to_i, TEST_TIME_SECONDS ].max
    @preview_time = format_preview_time(@preview_seconds)
  end

  def format_preview_time(seconds)
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    "#{hours}h #{minutes}m"
  end

  def test_time_granted?
    session[test_time_session_key].present?
  end

  def test_time_session_key
    "test_time_project_#{@project.id}"
  end
end
