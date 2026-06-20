module Notifications
  class AchievementEarned < ::Notification
    self.default_priority     = :low
    self.aggregatable         = false
    self.category_key         = :achievement_earned
    self.category_label       = "Achievements earned"
    self.category_description = "You unlocked a Stardance achievement"
    self.category_group       = "General"

    # Resolves the achievement from the record (a User::Achievement, which also
    # handles per-mission achievements) or, when none, from a slug in params.
    def achievement
      return record.achievement if record.respond_to?(:achievement)

      slug = params["achievement_slug"]
      slug.present? ? ::Achievement.slugged[slug.to_sym] : nil
    end

    def slack_message
      name = achievement&.name
      name.present? ? "🏆 You earned the *#{name}* achievement on Stardance!" : nil
    end

    def preview_text
      achievement&.description.to_s.truncate(140).presence
    end

    def email_subject
      name = achievement&.name
      name.present? ? "You earned the #{name} achievement" : "You earned a Stardance achievement"
    end
  end
end
