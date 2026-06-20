module Notifications
  class NewFollower < ::Notification
    self.default_priority     = :low
    self.aggregatable         = true
    self.category_key         = :new_follower
    self.category_label       = "New followers"
    self.category_description = "Someone started following you on Stardance"
    self.category_group       = "Social"
    self.digest_delay         = 1.hour

    def self.build_group_key(recipient:, **)
      "user_followed:#{recipient.id}"
    end

    def slack_message
      return nil unless actor&.slack_id.present?

      "✨ <@#{actor.slack_id}> just started following you on Stardance!"
    end

    def email_subject
      name = actor&.display_name
      name.present? ? "@#{name} started following you on Stardance" : "You have a new follower on Stardance"
    end
  end
end
