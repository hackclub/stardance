# frozen_string_literal: true

# == Schema Information
#
# Table name: user_achievements
#
#  id               :bigint           not null, primary key
#  achievement_slug :string           not null
#  earned_at        :datetime         not null
#  notified         :boolean          default(FALSE), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  user_id          :bigint           not null
#
# Indexes
#
#  index_user_achievements_on_user_id                       (user_id)
#  index_user_achievements_on_user_id_and_achievement_slug  (user_id,achievement_slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class User
  class Achievement < ApplicationRecord
    include Ledgerable

    self.table_name = "user_achievements"

    belongs_to :user

    validates :achievement_slug, presence: true
    validates :achievement_slug, uniqueness: { scope: :user_id }
    validate :achievement_slug_recognized
    validates :earned_at, presence: true

    after_create :grant_stardust_reward
    after_create_commit :notify_earned

    # Returns either a static `::Achievement` (Data.define struct) for slugs
    # in `::Achievement.all_slugs` OR a `Mission::AchievementProxy` for
    # dynamic per-mission slugs matching `/\Amission_[a-z0-9_-]+_completed\z/`.
    # Both honor the same interface (name, description, icon, slug,
    # has_stardust_reward?, stardust_reward).
    def achievement
      return ::Achievement.find(achievement_slug) if static_achievement?
      Mission::AchievementProxy.find(achievement_slug)
    end

    private

    def static_achievement?
      ::Achievement.all_slugs.map(&:to_s).include?(achievement_slug.to_s)
    end

    def achievement_slug_recognized
      return if static_achievement?
      return if Mission::AchievementProxy.matches?(achievement_slug)

      errors.add(:achievement_slug, "is not a known achievement")
    end

    def grant_stardust_reward
      return unless achievement&.has_stardust_reward?

      ledger_entries.create!(
        amount: achievement.stardust_reward,
        reason: "Achievement: #{achievement.name}",
        created_by: "achievement:#{achievement.slug}"
      )
    end

    def notify_earned
      ::Notifications::AchievementEarned.notify(recipient: user, record: self)
    end
  end
end
