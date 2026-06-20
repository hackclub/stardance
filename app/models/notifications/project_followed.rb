module Notifications
  class ProjectFollowed < ::Notification
    self.default_priority     = :medium
    self.aggregatable         = true
    self.slack_template_path  = "notifications/new_follower"
    self.category_key         = :project_followed
    self.category_label       = "New project followers"
    self.category_description = "Someone started following one of your projects"
    self.category_group       = "Social"
    self.digest_delay         = 1.hour
    self.inbox_record_preloads = []

    def self.build_group_key(record:, recipient:, **)
      "project_followed:#{record&.id || 0}:#{recipient.id}"
    end

    def slack_locals
      project = record
      return {} unless project

      {
        project_title: project.title,
        project_url:   Rails.application.routes.url_helpers.project_url(project, host: "stardance.hackclub.com", protocol: "https"),
        follower_id:   actor&.slack_id
      }
    end

    def email_subject
      who = actor&.display_name
      what = record&.title
      if who.present? && what.present?
        "@#{who} started following #{what}"
      elsif what.present?
        "Someone started following #{what}"
      else
        "Someone started following your project"
      end
    end
  end
end
