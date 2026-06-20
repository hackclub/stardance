module Notifications
  module Missions
    class SubmissionPendingForReviewer < ::Notification
      self.default_priority     = :medium
      self.aggregatable         = false
      self.slack_template_path  = "notifications/missions/submission_pending_for_reviewer.slack_message"
      self.category_key         = :mission_submission_pending_for_reviewer
      self.category_label       = "Mission submission pending review"
      self.category_description = "A submission is waiting for your review"
      self.category_group       = "Missions"
      self.inbox_record_preloads = :mission

      def slack_locals
        record&.notification_locals || {}
      end

      def email_subject
        mission = record&.mission&.name
        mission.present? ? "Submission awaiting your review on #{mission}" : "A submission is awaiting your review"
      end
    end
  end
end
