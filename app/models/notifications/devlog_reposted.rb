module Notifications
  class DevlogReposted < ::Notification
    self.default_priority      = :low
    self.aggregatable          = true
    self.category_key          = :devlog_reposted
    self.category_label        = "Reposts of your devlogs"
    self.category_description  = "Someone reposted one of your devlogs"
    self.category_group        = "Social"
    self.digest_delay          = 1.hour
    self.inbox_record_preloads = { post: :project }

    def self.build_group_key(record:, recipient:, **)
      "devlog_reposted:#{record&.id || 0}:#{recipient.id}"
    end

    def slack_message
      return nil unless actor&.slack_id.present?

      "🔁 <@#{actor.slack_id}> reposted your devlog on Stardance!"
    end

    def preview_text
      record&.body.to_s.truncate(140).presence
    end

    def preview_path
      project = record&.post&.project
      return nil unless project

      Rails.application.routes.url_helpers.project_devlog_path(project, record)
    end

    def email_subject
      who = actor&.display_name
      who.present? ? "@#{who} reposted your devlog" : "Someone reposted your devlog"
    end
  end
end
