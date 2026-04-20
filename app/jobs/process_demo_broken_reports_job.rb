class ProcessDemoBrokenReportsJob < ApplicationJob
  queue_as :default

  SLACK_RECIPIENT   = "U07L45W79E1"
  PENDING_THRESHOLD = 3
  TOTAL_THRESHOLD   = 15
  CACHE_TTL         = 7.days

  def perform
    host = default_host

    Project
      .joins(:reports)
      .includes(:users, :reports)
      .find_each(batch_size: 100) do |project|
      user = project.users.first
      reports = project.reports

      # 1. Auto-resolve reports for missing / banned users
      if user.nil? || user.banned?
        resolve_reports!(reports.pending)
        next
      end

      # Only demo_broken reports below
      demo_reports = reports.select { |r| r.reason == "demo_broken" }
      next if demo_reports.empty?

      pending_demo = demo_reports.select { |r| r.status == "pending" }

      # 2. Process pending demo_broken reports
      if pending_demo.size >= PENDING_THRESHOLD
        process_pending_reports!(
          project,
          pending_demo.first(PENDING_THRESHOLD)
        )
      end

      # 3. Slack notification threshold
      if demo_reports.size >= TOTAL_THRESHOLD && !notified?(project)
        notify_slack(project, demo_reports.size, host)
        mark_notified(project)
      end
    end
  end

  private

  # ----------------------------
  # Bulk helpers (NO N+1 writes)
  # ----------------------------

  def resolve_reports!(relation)
    return if relation.empty?

    relation.update_all(
      status: Project::Report.statuses[:reviewed],
      updated_at: Time.current
    )
  end

  def process_pending_reports!(project, reports)
    ids = reports.map(&:id)

    PaperTrail.request(whodunnit: nil) do
      Project::Report
        .where(id: ids)
        .update_all(
          status: Project::Report.statuses[:reviewed],
          updated_at: Time.current
        )
    end

    Rails.logger.info(
      "[ProcessDemoBrokenReportsJob] Marked #{ids.size} reports as reviewed for project #{project.id}"
    )

    ShipCertService.ship_to_dash(project, type: "demo_fixed")
  rescue => e
    Rails.logger.error(
      "[ProcessDemoBrokenReportsJob] Failed project #{project.id}: #{e.message}"
    )
  end

  # ----------------------------
  # Slack notification (cache-safe)
  # ----------------------------

  def notified?(project)
    Rails.cache.read(notification_key(project)) == true
  end

  def mark_notified(project)
    Rails.cache.write(notification_key(project), true, expires_in: CACHE_TTL)
  end

  def notify_slack(project, count, host)
    message =
      "🚨 Project '#{project.title}' (ID: #{project.id}) " \
      "has #{count} demo_broken reports.\n" \
      "Investigate: #{Rails.application.routes.url_helpers.project_url(project, host: host)}"

    SendSlackDmJob.perform_later(SLACK_RECIPIENT, message)
  end

  def notification_key(project)
    "demo_broken_notification:#{project.id}"
  end

  def default_host
    Rails.application.config.action_mailer.default_url_options&.dig(:host) ||
      "flavortown.hackclub.com"
  end
end
