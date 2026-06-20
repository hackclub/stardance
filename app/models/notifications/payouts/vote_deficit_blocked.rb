module Notifications
  module Payouts
    class VoteDeficitBlocked < ::Notification
      self.default_priority     = :medium
      self.aggregatable         = false
      self.slack_template_path  = "notifications/payouts/vote_deficit_blocked"
      self.category_key         = :vote_deficit_blocked
      self.category_label       = "Vote deficit blocking payout"
      self.category_description = "A ship event payout is blocked until you cast more votes"
      self.category_group       = "Stardust"

      def slack_locals
        ship = record
        {
          ship_event: ship,
          votes_needed: params["votes_needed"].to_i,
          project_title: params["project_title"]
        }
      end

      def email_subject
        n = params["votes_needed"].to_i
        n.positive? ? "Vote #{n} more time#{'s' if n != 1} to unlock your payout" : "Vote more to unlock your payout"
      end
    end
  end
end
