module Notifications
  module Workshops
    class StartingSoon < ::Notification
      self.default_priority     = :high
      self.category_key         = :workshop_starting_soon
      self.category_label       = "Workshop starting soon"
      self.category_description = "A workshop you RSVP'd to is about to begin"
      self.category_group       = "Workshops"
      self.inbox_record_preloads = []

      def slack_message
        return nil unless record

        ":telescope: *#{sanitize_slack_mentions(record.title)}* starts in #{Workshop::JOIN_WINDOW.inspect}! Head over to <#{workshop_url}|the workshop page> to join."
      end

      def email_subject
        record ? "#{record.title} starts in #{Workshop::JOIN_WINDOW.inspect}" : "Your workshop is about to start"
      end

      def workshop_url
        url_opts = Rails.application.config.action_controller.default_url_options
                        .reverse_merge(host: "stardance.hackclub.com", protocol: "https")
        Rails.application.routes.url_helpers.workshop_url(record, **url_opts)
      end
    end
  end
end
