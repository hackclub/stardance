module Notifications
  module Votes
    class Discarded < ::Notification
      self.default_priority     = :medium
      self.aggregatable         = true
      self.email_deliverable    = false
      self.category_key         = :discarded_vote
      self.category_label       = "Discarded ratings"
      self.category_description = "A recent rating did not pass quality checks and needs to be replaced"
      self.category_group       = "Voting"

      def self.build_group_key(recipient:, **)
        "discarded_votes:#{recipient.id}"
      end

      def effective_channels
        []
      end
    end
  end
end
