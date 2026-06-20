class Projects::LookoutSessionsController < ApplicationController
  before_action -> { head :not_found unless Flipper.enabled?(:hardware_flow, current_user) }
  before_action :set_project
  before_action :set_lookout_session, only: %i[show record stop set_mode forward_heartbeats]

  def create
    authorize @project, :create_devlog?

    # A session's tracked time is forwarded to Hackatime, so a linked Hackatime
    # account is required before one can be started.
    unless current_user.hackatime_identity.present?
      render json: { error: "Link your Hackatime account before recording a timelapse." }, status: :unprocessable_entity
      return
    end

    # projectName lets Lookout name the Hackatime project it forwards heartbeats
    # to, so the user can link it back to this project afterward.
    result = LookoutService.create_session(
      user_id: current_user.id,
      project_id: @project.id,
      project_name: @project.hackatime_recorder_name
    )

    unless result
      render json: { error: "Failed to create Lookout session" }, status: :service_unavailable
      return
    end

    @session = LookoutSession.create!(
      user: current_user,
      project: @project,
      token: result[:token],
      status: result[:status] || "pending",
      started_at: Time.current
    )

    render json: session_json(@session), status: :created
  end

  def show
    authorize @project, :create_devlog?

    remote = LookoutService.fetch_session(@lookout_session.token)
    sync_session!(@lookout_session, remote) if remote

    render json: session_json(@lookout_session)
  end

  # The recorder UI itself — opened in a new tab. Drives screen/webcam capture
  # against Lookout's client API straight from the browser, then lets the user
  # pick where the recorded time should go in Hackatime.
  def record
    authorize @project, :create_devlog?

    @lookout_api_base = LookoutService::BASE_URL
    @deep_link = "lookout://session?token=#{@lookout_session.token}"
    # Destination choices for the "where should this time go?" step shown once a
    # recording finishes: any of the user's existing Hackatime projects, or a
    # brand-new one (defaulting to this project's recorder name).
    @hackatime_project_names = current_user.hackatime_projects
                                           .where.not(name: User::HackatimeProject::EXCLUDED_NAMES)
                                           .order(:name)
                                           .pluck(:name)
    # A project can have several linked Hackatime projects. Surface them all
    # (grouped first in the destination chooser) and default-select one, so
    # recording from a project files the time back under one of its own by default.
    @linked_hackatime_names = @hackatime_project_names & @project.hackatime_keys
    @default_existing_hackatime_name = @linked_hackatime_names.first
    @default_hackatime_name = @project.hackatime_recorder_name
    render :record, layout: "lookout_recorder"
  end

  def stop
    authorize @project, :create_devlog?

    LookoutService.stop_session(@lookout_session.token)
    @lookout_session.update!(status: "stopped", stopped_at: Time.current)

    render json: session_json(@lookout_session)
  end

  # Records how the session is being captured (desktop / web / camera) so the
  # forwarded heartbeats can be tagged with the right Hackatime editor.
  def set_mode
    authorize @project, :create_devlog?

    mode = params[:mode].to_s
    return head :unprocessable_entity unless LookoutSession::MODES.include?(mode)

    @lookout_session.update!(mode: mode)
    head :ok
  end

  # Forwards a finished session's capture time to Hackatime under the project the
  # user chose on the recorder's "where should this time go?" step (server-side,
  # with the user's token). The recorder skips this call entirely when the user
  # picks "don't send to Hackatime".
  #
  # Runs synchronously and reports the outcome so the recorder can tell the user
  # if the time didn't make it (it's a handful of HTTP calls behind a "Sending
  # your time…" spinner). A background job that silently swallowed every failure
  # is exactly how a broken push went unnoticed before.
  def forward_heartbeats
    authorize @project, :create_devlog?

    project_name = params[:project_name].to_s.strip
    if project_name.blank? || User::HackatimeProject::EXCLUDED_NAMES.include?(project_name)
      return render json: { error: "Choose a Hackatime project to send your time to." }, status: :unprocessable_entity
    end

    result = LookoutHeartbeatForwarder.call(@lookout_session, project_name: project_name)
    if result.ok?
      render json: { ok: true, project: project_name, heartbeats: result.count }
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  def status
    authorize @project, :create_devlog?

    sessions = @project.lookout_sessions
                       .where(user: current_user)
                       .order(created_at: :desc)
                       .to_a

    # Sync any still-in-progress sessions from Lookout so status / duration /
    # video stay current even if the recorder tab was closed before stopping.
    sessions.each do |s|
      next if %w[complete failed].include?(s.status)

      remote = LookoutService.fetch_session(s.token)
      sync_session!(s, remote) if remote
    end

    render json: sessions.map { |s| session_json(s) }
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  # Scoped to the current user — a session belongs to whoever recorded it, so
  # members can only view/stop their own.
  def set_lookout_session
    @lookout_session = @project.lookout_sessions.where(user: current_user).find(params[:id])
  end

  # Mirror Lookout's client-API session state onto our row. The remote payload
  # is camelCase (trackedSeconds, videoUrl); tolerate snake_case too. Only accept
  # a status we recognize so update! can't blow up on a new remote state.
  # Heartbeat forwarding is user-driven (the recorder's destination step), so
  # this only syncs status / duration / video.
  def sync_session!(session, remote)
    status = remote[:status].presence_in(LookoutSession::STATUSES)
    tracked = remote[:trackedSeconds] || remote[:tracked_seconds] || remote[:duration_seconds]
    video   = remote[:videoUrl] || remote[:video_url] || remote[:recording_url]

    session.update!(
      status: status || session.status,
      duration_seconds: tracked ? tracked.to_i : session.duration_seconds,
      recording_url: video.presence || session.recording_url
    )
  end

  def session_json(session)
    {
      id: session.id,
      token: session.token,
      status: session.status,
      duration_seconds: session.duration_seconds,
      recording_url: session.recording_url,
      session_url: LookoutService.session_url_for(session.token),
      record_url: record_project_lookout_session_path(session.project, session),
      started_at: session.started_at&.iso8601,
      stopped_at: session.stopped_at&.iso8601
    }
  end
end
