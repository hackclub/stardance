module Notifications
  class MentionReceived < ::Notification
    self.default_priority     = :medium
    self.aggregatable         = false
    self.slack_template_path  = "notifications/mentions/mention_received_dm"
    self.category_key         = :mention_received
    self.category_label       = "Mentions"
    self.category_description = "Someone mentioned you in a comment or devlog"
    self.category_group       = "Social"
    self.inbox_record_preloads = []

    def slack_locals
      project = resolve_project
      return {} unless project

      {
        project_title: sanitize_slack_mentions(project.title),
        project_url:   Rails.application.routes.url_helpers.project_url(project, host: "stardance.hackclub.com", protocol: "https"),
        author_name:   sanitize_slack_mentions(actor&.display_name) || "Someone",
        comment_body:  sanitize_slack_mentions(record&.body.to_s.truncate(200))
      }
    end

    def preview_text
      record&.body.to_s.truncate(140).presence
    end

    def preview_path
      project = resolve_project
      return nil unless project

      if record.is_a?(Comment)
        commentable = record.commentable
        Rails.application.routes.url_helpers.project_devlog_path(
          project, commentable, anchor: "comment_#{record.id}"
        )
      elsif record.is_a?(Post::Devlog) && record.post
        Rails.application.routes.url_helpers.project_devlog_path(project, record)
      end
    end

    def email_subject
      project = resolve_project
      who = actor&.display_name
      if project&.title.present? && who.present?
        "@#{who} mentioned you on #{project.title}"
      elsif who.present?
        "@#{who} mentioned you"
      else
        "You were mentioned"
      end
    end

    def resolve_project
      case record
      when Comment
        commentable = record.commentable
        commentable.respond_to?(:post) ? commentable.post&.project : nil
      when Post::Devlog
        record.post&.project
      end
    end
  end
end
