module Project::ShipBlock
  extend ActiveSupport::Concern

  APPEAL_CHANNEL_ID = "C099P9FQQ91"
  APPEAL_CHANNEL_URL = "https://hackclub.enterprise.slack.com/archives/#{APPEAL_CHANNEL_ID}".freeze
  REASON_MAX_LENGTH = 10_000
  BLOCKED_MESSAGE = "This project is blocked from shipping, so it can't be shipped or re-certified. To appeal, send a message in #ask-the-shipwrights.".freeze

  def ship_blocked? = ship_block_reason.present?

  def owner_slack_id = memberships.owner.first&.user&.slack_id.presence

  def ship_block_notifies_owner? = !deleted? && owner_slack_id.present?

  def ship_block_version
    versions.where_attribute_changes(:ship_block_reason).reorder(created_at: :desc).first
  end

  def ship_blocked_by(version = ship_block_version)
    version && User.find_by(id: version.whodunnit)
  end

  def block_shipping!(by:, reason:)
    raise ArgumentError, "a ship block needs a reason" if reason.blank?

    blocked = update_ship_block!(reason, expected_blocked: false)
    if blocked
      dm_owner_about_ship_block("ship_blocked", sent_by: by,
                                text: "Your project '#{title}' was blocked from shipping and can't be shipped or re-certified.",
                                reason: reason, appeal_channel_id: APPEAL_CHANNEL_ID)
    end
    blocked
  end

  def unblock_shipping!(by:)
    unblocked = update_ship_block!(nil, expected_blocked: true)
    if unblocked
      dm_owner_about_ship_block("ship_unblocked", sent_by: by,
                                text: "Your project '#{title}' was unblocked. You can ship it again.")
    end
    unblocked
  end

  private

  # validate: false because an admin decision must not be blocked by an
  # unrelated validation a legacy project no longer passes.
  def update_ship_block!(reason, expected_blocked:)
    with_lock do
      next false unless ship_blocked? == expected_blocked

      self.ship_block_reason = reason
      save!(validate: false)
    end
  end

  def dm_owner_about_ship_block(template, sent_by:, text:, **locals)
    return unless ship_block_notifies_owner?

    url_opts = (Rails.application.config.action_controller.default_url_options || {})
      .reverse_merge(host: "stardance.hackclub.com", protocol: "https")
    SendSlackDmJob.perform_later(
      owner_slack_id,
      text,
      blocks_path: "notifications/projects/#{template}",
      locals: {
        project_title: title,
        project_url: Rails.application.routes.url_helpers.project_url(self, **url_opts),
        **locals
      },
      sent_by_id: sent_by.id
    )
  end
end
