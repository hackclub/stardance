module Notifications
  # A quote-repost (a repost carrying its own commentary) stands on its own so
  # the quote text is visible — unlike plain reposts, which aggregate.
  class DevlogQuoteReposted < ::Notification
    self.default_priority      = :low
    self.aggregatable          = false
    self.category_key          = :devlog_quote_reposted
    self.category_label        = "Quote reposts of your devlogs"
    self.category_description  = "Someone quote-reposted one of your devlogs with their own note"
    self.category_group        = "Social"
    self.inbox_record_preloads = { original_post: :project }

    def slack_message
      return nil unless actor&.slack_id.present?

      "🔁 <@#{actor.slack_id}> quote-reposted your devlog on Stardance!"
    end

    def preview_text
      record&.body.to_s.truncate(140).presence
    end

    # Jump to the devlog that was quote-reposted (reposts have no permalink of
    # their own; the original devlog is the meaningful destination).
    def preview_path
      original = record&.original_post
      devlog = original&.postable
      return nil unless original&.project && devlog.is_a?(Post::Devlog)

      Rails.application.routes.url_helpers.project_devlog_path(original.project, devlog)
    end

    def email_subject
      who = actor&.display_name
      who.present? ? "@#{who} quote-reposted your devlog" : "Someone quote-reposted your devlog"
    end
  end
end
