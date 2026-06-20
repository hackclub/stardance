module Notifications
  module Projects
    class SuperStar < ::Notification
      self.default_priority     = :high
      self.aggregatable         = false
      self.slack_template_path  = "notifications/projects/super_star"
      self.category_key         = :project_super_star
      self.category_label       = "Super Star projects"
      self.category_description = "Your project was marked as a Super Star"
      self.category_group       = "Missions"
      self.inbox_record_preloads = []

      def slack_locals
        record ? { project: record } : {}
      end

      def email_subject
        title = record&.title
        title.present? ? "#{title} was marked a Super Star" : "Your project was marked a Super Star"
      end
    end
  end
end
