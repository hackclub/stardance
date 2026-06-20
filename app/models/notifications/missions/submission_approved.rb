module Notifications
  module Missions
    class SubmissionApproved < ::Notification
      self.default_priority     = :high
      self.aggregatable         = false
      self.slack_template_path  = "notifications/missions/submission_approved.slack_message"
      self.category_key         = :mission_submission_approved
      self.category_label       = "Mission submission approved"
      self.category_description = "Your ship event passed mission review"
      self.category_group       = "Missions"
      self.inbox_record_preloads = :mission

      def slack_locals
        record&.notification_locals || {}
      end

      def email_subject
        mission = record&.mission&.name
        mission.present? ? "#{mission} submission approved" : "Your mission submission was approved"
      end
    end
  end
end
