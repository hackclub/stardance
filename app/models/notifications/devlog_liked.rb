module Notifications
  class DevlogLiked < ::Notification
    self.default_priority      = :low
    self.aggregatable          = true
    self.category_key          = :devlog_liked
    self.category_label        = "Likes on your devlogs"
    self.category_description  = "Someone liked one of your devlogs"
    self.category_group        = "Social"
    self.digest_delay          = 1.hour
    self.inbox_record_preloads = { post: :project }

    def self.build_group_key(record:, recipient:, **)
      "devlog_liked:#{record&.id || 0}:#{recipient.id}"
    end

    def slack_message
      return nil unless actor&.slack_id.present?

      "❤️ <@#{actor.slack_id}> liked your devlog on Stardance!"
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
      who.present? ? "@#{who} liked your devlog" : "Someone liked your devlog"
    end
  end
end
