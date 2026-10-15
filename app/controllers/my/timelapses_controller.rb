class My::TimelapsesController < ApplicationController
  before_action :require_login

  # Temporary recovery hub: every Lookout recording this builder has with tracked
  # time, so they can confirm each one's time reached Hackatime and push any that
  # didn't. Each row links to its per-session finalize page. Retired with the
  # rest of the recovery surface after LookoutSession::FINALIZE_DEADLINE.
  def index
    @deadline = LookoutSession::FINALIZE_DEADLINE
    @window_open = Time.current <= @deadline
    # Only sessions whose project still exists: Project's default_scope hides
    # soft-deleted rows, so an orphaned session's `project` is nil and the view
    # (and forward path) would blow up. A deleted project can't be recovered to
    # anyway.
    @sessions = LookoutSession.where(user: current_user)
                              .recoverable
                              .where(project_id: Project.select(:id))
                              .includes(:project)
                              .order(Arel.sql("COALESCE(started_at, created_at) DESC"))
    # Which sessions Hackatime already has, matched exactly by heartbeat entity
    # (see LookoutPushStatus). Cached per user; ?recheck re-scans.
    @pushed_tokens = LookoutPushStatus.pushed_tokens(user: current_user, refresh: params[:recheck].present?)
  end

  private

  def require_login
    redirect_to root_path, alert: "Please log in first" and return unless current_user
  end
end
