module Notifications
  module Hardware
    # A verdict on a hardware funding request. One type covers both outcomes:
    # a builder wants to hear about the decision either way, and splitting them
    # would let someone mute the approval while still getting the rejection.
    # Copy branches on the record's status.
    class FundingRequestReviewed < ::Notification
      self.default_priority     = :high
      self.aggregatable         = false
      # No .slack_message suffix: SendSlackDmJob passes this straight to the
      # renderer with formats: [:slack_message], so a suffixed path raises
      # MissingTemplate and the DM is swallowed by the job's rescue.
      self.slack_template_path  = "notifications/hardware/funding_request_reviewed"
      self.category_key         = :funding_request_reviewed
      self.category_label       = "Funding request reviewed"
      self.category_description = "Your hardware funding request was approved or sent back"
      self.category_group       = "Hardware"
      self.inbox_record_preloads = :project

      def slack_locals
        record&.notification_locals || {}
      end

      def email_subject
        title = record&.project&.title
        if record&.approved?
          approval = record.issues_grant? ? "approved for funding" : "approved"
          title.present? ? "#{title} was #{approval}" : "Your funding request was approved"
        else
          title.present? ? "#{title} needs changes before funding" : "Your funding request needs changes"
        end
      end
    end
  end
end
