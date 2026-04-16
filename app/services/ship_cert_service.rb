class ShipCertService
  WEBHOOK_URL = ENV["SW_DASHBOARD_WEBHOOK_URL"]
  CERT_API_KEY = ENV["SW_DASHBOARD_API_KEY"]
  USER_AGENT = "Stardance/1.0 (ShipCertService)"

  def self.ship_data(project, type: nil, ship_event: nil)
    owner = project.memberships.owner.first&.user
    ship_event ||= latest_ship_event(project)
    sidequest_entries = project.sidequest_entries.includes(:sidequest)
    sidequest_slugs = sidequest_entries.map { |entry| entry.sidequest&.slug }.compact
    sidequest_details = sidequest_entries.filter_map do |entry|
      sidequest = entry.sidequest
      next unless sidequest

      {
        id: sidequest.id.to_s,
        slug: sidequest.slug,
        title: sidequest.title,
        entryState: entry.aasm_state
      }
    end

    devlog_count = project.devlog_posts
      .joins("JOIN post_devlogs ON post_devlogs.id = posts.postable_id")
      .where(post_devlogs: { deleted_at: nil })
      .size

    last_ship_at = project.ship_events.first&.created_at

    {
      event: "ship.submitted",
      data: {
        id: project.id.to_s,
        shipEventId: ship_event&.id&.to_s,
        projectName: project.title,
        submittedBy: {
          slackId: owner&.slack_id,
          username: owner&.display_name || "Not Found"
        },
        projectType: project.project_type,
        type: type,
        description: project.description,
        reviewInstructions: ship_event&.review_instructions,
        links: {
          demo: project.demo_url,
          repo: project.repo_url,
          readme: project.readme_url
        },
        metadata: {
          devTime: project.duration_seconds,
          devlogCount: devlog_count,
          lastShipEventAt: last_ship_at&.iso8601,
          isSidequestProject: sidequest_slugs.any?,
          sidequestSlugs: sidequest_slugs,
          sidequests: sidequest_details
        }
      }
    }
  end

  ALERT_CHANNEL = "C0AJS1H6R42"

  def self.ship_to_dash(project, type: nil)
    ship_event = latest_ship_event(project)
    return false unless ship_event

    send_webhook(project, type: type, ship_event: ship_event)
    true
  rescue => e
    notify_slack_of_failure(project, type: type, ship_event: ship_event, error: e)
    raise e
  end

  def self.send_webhook(project, type: nil, ship_event: nil)
    raise "SW_DASHBOARD_WEBHOOK_URL is not configured" unless WEBHOOK_URL.present?
    raise "SW_DASHBOARD_API_KEY is not configured" unless CERT_API_KEY.present?

    response = Faraday.post(WEBHOOK_URL) do |req|
      req.headers["Content-Type"] = "application/json"
      req.headers["User-Agent"] = USER_AGENT
      req.headers["x-api-key"] = CERT_API_KEY
      req.options.open_timeout = 5
      req.options.timeout = 10
      req.body = ship_data(project, type: type, ship_event: ship_event).to_json
    end

    if response.success?
      Rails.logger.info "#{project.id} sent for certification"
      true
    else
      raise "Certification request failed for project #{project.id}: #{response.body}"
    end
  rescue Faraday::Error => e
    Rails.logger.error "cert request error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
    raise e
  end

  def self.get_status(project)
    ship_event = latest_ship_event(project)
    return nil unless ship_event

    ship_event.certification_status
  end

  def self.get_feedback(project)
    ship_event = latest_ship_event(project)
    return nil unless ship_event

    {
      status: ship_event.certification_status,
      video_url: ship_event.feedback_video_url,
      reason: ship_event.feedback_reason
    }
  end

  def self.latest_ship_event(project)
    project.ship_event_posts.order(created_at: :desc).first&.postable
  end

  def self.notify_slack_of_failure(project, type:, ship_event:, error:)
    payload = ship_data(project, type: type, ship_event: ship_event)
    message = [
      ":rotating_light: Ship cert webhook failed for project #{project.id} (#{project.title})",
      "Type: #{type || 'nil'}",
      "Ship Event ID: #{ship_event&.id || 'nil'}",
      "Error: #{error.class} - #{error.message}",
      "Webhook URL: #{WEBHOOK_URL}",
      "Payload: #{payload.to_json}"
    ].join("\n")

    SendSlackDmJob.perform_later(ALERT_CHANNEL, message)
  rescue => slack_error
    Rails.logger.error "Failed to send ship cert failure Slack alert: #{slack_error.message}"
  end
end
