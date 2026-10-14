module Notifications
  module Hardware
    # A reviewer reversed a decided hardware review (funding request or ship
    # certification). The original verdict message can't be unsent, so this is
    # the correction: it tells the builder the decision was rolled back and the
    # review is being looked at again.
    class ReviewUndone < ::Notification
      self.default_priority     = :high
      self.aggregatable         = false
      # No .slack_message suffix: SendSlackDmJob passes this straight to the
      # renderer with formats: [:slack_message], so a suffixed path raises
      # MissingTemplate and the DM is swallowed by the job's rescue.
      self.slack_template_path  = "notifications/hardware/review_undone"
      self.category_key         = :review_undone
      self.category_label       = "Review undone"
      self.category_description = "A verdict on your hardware review was reversed"
      self.category_group       = "Hardware"
      self.inbox_record_preloads = :project

      def slack_locals
        {
          project_title: record&.project&.title,
          project_url: record ? project_url_for(record.project) : nil,
          review_type: record.is_a?(Certification::FundingRequest) ? "funding request" : "ship certification"
        }
      end

      def email_subject
        title = record&.project&.title
        title.present? ? "The review of #{title} was reopened" : "Your hardware review was reopened"
      end

      private

      def project_url_for(project)
        return nil unless project

        routes = Rails.application.routes.url_helpers
        url_opts = (Rails.application.config.action_controller.default_url_options || {})
                     .reverse_merge(host: "stardance.hackclub.com", protocol: "https")
        routes.project_url(project, **url_opts)
      end
    end
  end
end
