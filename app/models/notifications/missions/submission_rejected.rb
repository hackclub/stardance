module Notifications
  module Missions
    class SubmissionRejected < ::Notification
      self.default_priority     = :high
      self.aggregatable         = false
      self.slack_template_path  = "notifications/missions/submission_rejected.slack_message"
      self.category_key         = :mission_submission_rejected
      self.category_label       = "Mission submission rejected"
      self.category_description = "Your ship event was sent back with feedback"
      self.category_group       = "Missions"
      self.inbox_record_preloads = :mission

      def slack_locals
        record&.notification_locals || {}
      end

      def email_subject
        mission = record&.mission&.name
        mission.present? ? "#{mission} submission needs revisions" : "Your mission submission needs revisions"
      end
    end
  end
end
