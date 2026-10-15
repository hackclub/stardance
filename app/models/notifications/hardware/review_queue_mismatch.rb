module Notifications
  module Hardware
    # A reviewer says a hardware submission is in the wrong queue: a build ship
    # that should have asked for funding first, or a design request from someone
    # who has already finished building. Nothing moves until the builder answers
    # it on their project page, so this is high priority and not mutable.
    class ReviewQueueMismatch < ::Notification
      self.default_priority     = :high
      self.aggregatable         = false
      self.slack_template_path  = "notifications/hardware/review_queue_mismatch"
      self.category_key         = :review_queue_mismatch
      self.category_label       = "Submission in the wrong queue"
      self.category_description = "A reviewer thinks your hardware submission belongs in the other queue"
      self.category_group       = "Hardware"
      self.inbox_record_preloads = :project

      def slack_locals
        record&.queue_mismatch_notification_locals || {}
      end

      def email_subject
        title = record&.project&.title
        return "Your hardware submission needs a quick answer" if title.blank?

        "#{title} needs a quick answer before it can be reviewed"
      end
    end
  end
end
