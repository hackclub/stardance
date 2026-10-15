class Projects::LookoutSessionsController < ApplicationController
  # Temporary recovery surface. Retiring the in-app Lookout recorder removed the
  # "send your time to Hackatime" step out from under builders who were still
  # mid-recording, stranding their tracked time. This lets a session's owner
  # finalize it: watch the timelapse and push its time to Hackatime. It stays
  # open until LookoutSession::FINALIZE_DEADLINE, after which the whole surface
  # closes again. The list view lives at My::TimelapsesController.
  before_action :set_project
  before_action :ensure_finalize_window_open
  before_action :set_lookout_session

  # Where the builder lands the recovery: a live status sync, their timelapse
  # preview, and the "where should this time go?" destination chooser.
  def finalize
    authorize @project, :show?

    # A recording left active/paused when the recorder went away won't have final
    # timings until Lookout stops it, so finalize it first.
    LookoutService.stop_session(@lookout_session.token) unless @lookout_session.terminal?
    remote = LookoutService.fetch_session(@lookout_session.token)
    @lookout_session.sync_from_remote!(remote) if remote

    @finalize_deadline = LookoutSession::FINALIZE_DEADLINE
    @already_pushed = LookoutPushStatus.pushed_tokens(user: current_user, refresh: params[:recheck].present?)
                                       .include?(@lookout_session.token)
    @recording = LookoutService.recording_for_session(@lookout_session)
    @hackatime_project_names = current_user.hackatime_projects
                                           .where.not(name: User::HackatimeProject::EXCLUDED_NAMES)
                                           .order(:name)
                                           .pluck(:name)
    @linked_hackatime_names = @hackatime_project_names & @project.hackatime_keys

    # Best guess for where this time belongs: the project's own recorder name (its
    # title), which is what the session was created to file against. Prefer an
    # existing Hackatime project of that name, then any already linked to this
    # project; otherwise offer to create it new.
    @default_hackatime_name = @project.hackatime_recorder_name
    @default_existing_hackatime_name =
      (@default_hackatime_name if @hackatime_project_names.include?(@default_hackatime_name)) ||
      @linked_hackatime_names.first
    @prefer_existing = @default_existing_hackatime_name.present?
  end

  # Push the session's captured time into the chosen Hackatime project. Runs
  # synchronously so we can tell the builder whether it actually landed.
  def forward_heartbeats
    authorize @project, :show?

    project_name = chosen_project_name
    if project_name.blank? || User::HackatimeProject::EXCLUDED_NAMES.include?(project_name)
      return redirect_to finalize_project_lookout_session_path(@project, @lookout_session),
                         alert: "Choose a Hackatime project to send your time to."
    end

    result = LookoutHeartbeatForwarder.call(@lookout_session, project_name: project_name)
    if result.ok?
      LookoutPushStatus.expire(current_user)
      redirect_to my_timelapses_path,
                  notice: "Sent your time to #{project_name}. It counts toward the project once you post a devlog."
    else
      redirect_to finalize_project_lookout_session_path(@project, @lookout_session), alert: result.error
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def ensure_finalize_window_open
    return if Time.current <= LookoutSession::FINALIZE_DEADLINE

    redirect_to project_path(@project),
                alert: "The Lookout recovery window has closed. Record your time on Lapse instead."
  end

  # Owner-scoped: a session belongs to whoever recorded it, so only they can
  # finalize their own.
  def set_lookout_session
    @lookout_session = @project.lookout_sessions.where(user: current_user).find(params[:id])
  end

  # The destination chooser is plain HTML (no JS), so it posts the picked mode
  # plus both candidate names; resolve which one the builder actually meant here.
  def chosen_project_name
    if params[:dest] == "new"
      params[:new_project_name].to_s.strip
    else
      params[:existing_project_name].to_s.strip.presence || params[:new_project_name].to_s.strip
    end
  end
end
