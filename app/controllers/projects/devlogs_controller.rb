class Projects::DevlogsController < ApplicationController
  before_action :set_project
  before_action :set_devlog, only: %i[edit update destroy versions]
  before_action :require_hackatime_project, only: %i[new create]
  before_action :sync_hackatime_projects, only: %i[new create]
  before_action :load_preview_time, only: %i[new]
  before_action :require_preview_time, only: %i[new]
  before_action :load_lapse_timelapses, only: %i[new create]

  def new
    authorize @project, :create_devlog?
    @devlog = Post::Devlog.new
  end

  def create
    authorize @project, :create_devlog?

    current_user.with_advisory_lock("devlog_create", timeout_seconds: 10) do
      load_preview_time
      return redirect_to @project, alert: "Could not calculate your coding time. Please try again." unless @preview_time.present?

      @devlog = Post::Devlog.new(devlog_params.except(:lapse_timelapse_id))
      @devlog.duration_seconds = @preview_seconds
      @devlog.hackatime_projects_key_snapshot = @project.hackatime_keys.join(",")

      if params[:media_type] == "lapse"
        timelapse_data = resolve_lapse_timelapse
        unless timelapse_data
          flash.now[:alert] = "Failed to attach timelapse. Please try again or use a file upload."
          load_lapse_timelapses
          return render :new, status: :unprocessable_entity
        end
        @devlog.lapse_video_processing = true
      end

      if @devlog.save
        if timelapse_data
          ProcessLapseTimelapseJob.perform_later(@devlog.id, timelapse_data[:id], timelapse_data[:playback_url])
        end
        Post.create!(project: @project, user: current_user, postable: @devlog)
        Rails.cache.delete("user/#{current_user.id}/devlog_seconds_total")
        Rails.cache.delete("user/#{current_user.id}/devlog_seconds_today/#{Time.zone.today}")
        flash[:notice] = "Devlog created successfully"

        unless @devlog.tutorial?
          existing_non_tutorial_devlogs = Post::Devlog.joins(:post)
                                                      .where(posts: { user_id: current_user.id })
                                                      .where(tutorial: false)
                                                      .where.not(id: @devlog.id)
          if existing_non_tutorial_devlogs.empty?
            FunnelTrackerService.track(
              event_name: "devlog_created",
              user: current_user,
              properties: { devlog_id: @devlog.id, project_id: @project.id }
            )
          end
        end

        if current_user.complete_tutorial_step! :post_devlog
          tutorial_message [
            "Yay! You just earned free stickers for posting your first devlog — claim them from the Kitchen!",
            "Now ship your project (when it is cooked to your satisfaction) to earn cookies 🍪 and exchange those for stuff in the shop.",
            "Bonne chance! Remember, anyone can cook — go forth and whip up a storm!"
          ]
        end

        return redirect_to @project
      else
        flash.now[:alert] = @devlog.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
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

      redirect_to @project, notice: "Devlog updated successfully"
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
      redirect_to @project and return
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
    redirect_to @project, notice: "Devlog deleted successfully"
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
    unless @project.hackatime_keys.present?
      redirect_to edit_project_path(@project), alert: "You must link at least one Hackatime project before posting a devlog" and return
    end
  end

  def sync_hackatime_projects
    owner = @project.memberships.owner.first&.user
    return unless owner

    owner.try_sync_hackatime_data!
    @project.reload
  end

  def require_preview_time
    unless @preview_time.present?
      @retry_count = (params[:retry] || 0).to_i
      if @retry_count < 3
        @show_loading = true
        render :loading and return
      else
        redirect_to @project, alert: "Could not fetch your coding time from Hackatime after multiple attempts. Please ensure Hackatime is tracking your project." and return
      end
    end
  end

  def devlog_params
    params.require(:post_devlog).permit(:body, :lapse_timelapse_id, attachments: [])
  end

  def update_devlog_params
    params.require(:post_devlog).permit(:body, attachments: [])
  end

  def load_preview_time
    @preview_seconds = 0
    @project.reload
    hackatime_keys = @project.hackatime_keys

    Rails.logger.info "DevlogsController#load_preview_time: project=#{@project.id}, hackatime_keys=#{hackatime_keys.inspect}"

    return @preview_time = nil unless hackatime_keys.present?

    hackatime_uid = current_user.hackatime_identity&.uid
    return @preview_time = nil unless hackatime_uid.present?

    total_seconds = HackatimeService.fetch_total_seconds_for_projects(hackatime_uid, hackatime_keys)
    return @preview_time = nil unless total_seconds

    already_logged = Post::Devlog.where(
      id: @project.posts.where(postable_type: "Post::Devlog").select("postable_id::bigint")
    ).sum(:duration_seconds) || 0

    @preview_seconds = [ total_seconds - already_logged, 0 ].max
    hours = @preview_seconds / 3600
    minutes = (@preview_seconds % 3600) / 60
    @preview_time = "#{hours}h #{minutes}m"
  rescue => e
    Rails.logger.error "Failed to load preview time: #{e.message}"
    @preview_time = nil
  end

  def resolve_lapse_timelapse
    timelapse_id = devlog_params[:lapse_timelapse_id]
    return nil unless timelapse_id.present?

    timelapse = @lapse_timelapses&.find { |t| t["id"] == timelapse_id }
    return nil unless timelapse

    playback_url = timelapse["playbackUrl"]
    return nil unless playback_url.present?

    { id: timelapse_id, playback_url: playback_url }
  end

  def load_lapse_timelapses
    @lapse_timelapses = []

    hackatime_identity = current_user.hackatime_identity
    unless hackatime_identity&.uid.present?
      return
    end

    unless ENV["LAPSE_API_BASE"].present?
      return
    end

    hackatime_keys = @project.hackatime_keys
    unless hackatime_keys.present?
      return
    end

    all_timelapses = LapseService.fetch_all_timelapses_for_projects(
      hackatime_user_id: hackatime_identity.uid,
      project_keys: hackatime_keys
    )

    return unless all_timelapses.present?

    last_devlog = @project.devlogs.order(created_at: :desc).first
    last_devlog_time = last_devlog&.created_at

    @lapse_timelapses = all_timelapses.select do |timelapse|
      created_at = Time.at(timelapse["createdAt"].to_i / 1000.0) rescue nil
      next false unless created_at

      if last_devlog_time
        created_at > last_devlog_time
      else
        true
      end
    end
  rescue => e
    Rails.logger.error "Failed to load lapse timelapses: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    @lapse_timelapses = []
  end
end
