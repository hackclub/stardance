class DevlogCapWarningJob < ApplicationJob
  queue_as :literally_whenever

  # Only projects showing recent signs of life get checked: created recently
  # or devlogged recently.
  ACTIVITY_WINDOW = 14.days
  # Pause between Hackatime calls so the hourly sweep stays well inside the
  # API rate limit (360 req/min, shared with the rest of the app).
  API_PAUSE_SECONDS = 0.5

  def perform
    candidate_projects.find_each(batch_size: 200) do |project|
      check_project(project)
    end
  end

  private

  def candidate_projects
    recently_devlogged = Post.where(postable_type: "Post::Devlog")
                             .where(created_at: ACTIVITY_WINDOW.ago..)
                             .select(:project_id)

    base = Project.joins(:hackatime_projects).distinct
    base.where(created_at: ACTIVITY_WINDOW.ago..).or(base.where(id: recently_devlogged))
        .includes(memberships: { user: :hackatime_identity })
  end

  def check_project(project)
    owner = project.memberships.detect(&:owner?)&.user
    identity = owner&.hackatime_identity
    return unless identity
    return if owner.banned?

    # Un-devlogged time can't exceed wall-clock time since the window opened,
    # so recently-devlogged projects can be skipped without an API call.
    window_start = project.devlog_window_start(Time.current)
    return if Time.current - window_start < Post::ShipEvent::DEVLOG_CAP_WARNING_SECONDS
    return if already_notified?(project, owner, window_start)

    unposted = project.seconds_coded_in_devlog_window(identity.uid, access_token: identity.access_token).to_i
    sleep API_PAUSE_SECONDS
    return if unposted < Post::ShipEvent::DEVLOG_CAP_WARNING_SECONDS

    Notifications::Projects::DevlogCapApproaching.notify(
      recipient: owner,
      record: project,
      params: { "unposted_seconds" => unposted }
    )
  end

  # One nudge per devlog window: posting a devlog re-arms the warning.
  def already_notified?(project, owner, window_start)
    Notifications::Projects::DevlogCapApproaching
      .where(recipient: owner, record: project)
      .where(created_at: window_start..)
      .exists?
  end
end
