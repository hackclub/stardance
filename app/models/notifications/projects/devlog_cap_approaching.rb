module Notifications
  module Projects
    class DevlogCapApproaching < ::Notification
      self.default_priority     = :high
      self.aggregatable         = false
      self.slack_template_path  = "notifications/projects/devlog_cap_approaching"
      self.category_key         = :devlog_cap_approaching
      self.category_label       = "Un-devlogged time warnings"
      self.category_description = "You're nearing the #{Post::ShipEvent::MAX_PAYOUT_HOURS_PER_DEVLOG}-hour per-devlog payout cap on time without a devlog"
      self.category_group       = "Stardust"
      self.inbox_record_preloads = []

      # Payout-affecting warning, not an engagement feature, so deliberately
      # not gated behind the week_2_release notifications rollout flag.
      def self.enabled_for?(user)
        user.present?
      end

      def unposted_time_text
        ApplicationController.helpers.format_hours_minutes(params["unposted_seconds"])
      end

      def slack_locals
        record ? { project: record, unposted_time: unposted_time_text } : {}
      end

      def email_subject
        cap = "#{Post::ShipEvent::MAX_PAYOUT_HOURS_PER_DEVLOG}-hour"
        title = record&.title
        title.present? ? "Post a devlog on #{title}- you're nearing the #{cap} cap" : "Post a devlog- you're nearing the #{cap} cap"
      end
    end
  end
end
