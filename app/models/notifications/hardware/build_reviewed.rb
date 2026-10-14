module Notifications
  module Hardware
    # A verdict on a hardware build's ship certification. One type covers both
    # outcomes, as in [FundingRequestReviewed]: splitting them would let someone
    # mute the approval while still getting the rejection.
    class BuildReviewed < ::Notification
      self.default_priority     = :high
      self.aggregatable         = false
      # No .slack_message suffix: SendSlackDmJob passes this straight to the
      # renderer with formats: [:slack_message], so a suffixed path raises
      # MissingTemplate and the DM is swallowed by the job's rescue.
      self.slack_template_path  = "notifications/hardware/build_reviewed"
      self.category_key         = :build_reviewed
      self.category_label       = "Build reviewed"
      self.category_description = "Your hardware build was approved or sent back"
      self.category_group       = "Hardware"
      self.inbox_record_preloads = :project

      def slack_locals
        record&.notification_locals || {}
      end

      def email_subject
        title = record&.project&.title
        if record&.approved?
          title.present? ? "#{title} was approved" : "Your build was approved"
        else
          title.present? ? "#{title} needs changes" : "Your build needs changes"
        end
      end
    end
  end
end
