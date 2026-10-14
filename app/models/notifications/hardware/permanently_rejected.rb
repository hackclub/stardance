module Notifications
  module Hardware
    class PermanentlyRejected < ::Notification
      self.default_priority = :high
      self.aggregatable = false
      self.slack_template_path = "notifications/hardware/permanently_rejected"
      self.category_key = :hardware_permanently_rejected
      self.category_label = "Hardware project permanently rejected"
      self.category_description = "An administrator made a final decision on your hardware project"
      self.category_group = "Hardware"
      self.inbox_record_preloads = :project

      def slack_locals
        record&.notification_locals&.slice(:project_title, :project_url, :feedback) || {}
      end

      def email_subject
        "#{record&.project&.title || 'Your hardware project'} was permanently rejected"
      end

      def preview_text
        record&.feedback
      end
    end
  end
end
