module Notifications
  class FollowedDevlogCreated < ::Notification
    self.default_priority     = :low
    self.aggregatable         = true
    self.slack_template_path  = "notifications/creations/followed_devlog_created"
    self.category_key         = :followed_devlog_created
    self.category_label       = "Devlogs on followed projects"
    self.category_description = "A new devlog was posted on a project you follow"
    self.category_group       = "Social"
    self.inbox_record_preloads = { post: :project }

    def self.build_group_key(record:, recipient:, **)
      project = record.is_a?(Post::Devlog) ? record.post&.project : nil
      "followed_devlog:#{project&.id || 0}:#{recipient.id}"
    end

    def slack_locals
      devlog = record
      project = devlog&.post&.project
      author = devlog&.post&.user
      return {} unless project && author

      {
        project_title: sanitize_slack_mentions(project.title),
        project_url:   Rails.application.routes.url_helpers.project_url(project, host: "stardance.hackclub.com", protocol: "https"),
        author_name:   sanitize_slack_mentions(author.display_name) || "Someone",
        devlog_body:   sanitize_slack_mentions(devlog.body.to_s.truncate(200))
      }
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
      project = record&.post&.project
      project&.title.present? ? "New devlog on #{project.title}" : "New devlog on a project you follow"
    end
  end
end
