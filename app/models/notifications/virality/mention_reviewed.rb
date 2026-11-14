module Notifications
  module Virality
    class MentionReviewed < ::Notification
      self.default_priority     = :high
      self.aggregatable         = false
      self.slack_template_path  = "notifications/virality/mention_reviewed"
      self.category_key         = :virality_mention_reviewed
      self.category_label       = "Viral mention reviewed"
      self.category_description = "A viral mention you submitted was approved, rejected or reopened"
      self.category_group       = "Stardust"
      self.inbox_record_preloads = { project_mention: :project }

      def slack_locals
        record&.notification_locals || {}
      end

      def preview_text
        record&.reason.to_s.truncate(140).presence
      end

      def email_subject
        title = record&.project_mention&.project&.title
        subject = title.present? ? "Your viral mention for #{title}" : "Your viral mention"
        case record&.action
        when "approve" then "#{subject} was approved"
        when "reject" then "#{subject} wasn't approved"
        else "#{subject} is back in review"
        end
      end
    end
  end
end
