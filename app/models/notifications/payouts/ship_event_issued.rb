module Notifications
  module Payouts
    class ShipEventIssued < ::Notification
      self.default_priority     = :high
      self.aggregatable         = false
      # The payout email is delivered through the Airtable -> Loops user sync,
      # not the app's SMTP mailer, which Loops' relay rejects (450, not a valid
      # JSON payload). Keep this notification in-app + Slack only so we don't
      # fire a second, broken SMTP email on every payout.
      self.email_deliverable    = false
      self.slack_template_path  = "notifications/payouts/ship_event_issued"
      self.category_key         = :ship_event_payout_issued
      self.category_label       = "Ship event payouts"
      self.category_description = "Stardust was paid out for one of your ship events"
      self.category_group       = "Stardust"

      def slack_locals
        params.symbolize_keys.slice(:project_title, :ship_date, :hours, :stardust, :multiplier, :blessing)
      end

      def email_subject
        title = params["project_title"]
        title.present? ? "Payout issued for #{title}" : "Ship event payout issued"
      end
    end
  end
end
