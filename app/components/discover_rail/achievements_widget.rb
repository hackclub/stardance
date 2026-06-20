# frozen_string_literal: true

module DiscoverRail
  class AchievementsWidget < BaseWidget
    register_as :achievements

    def profile_user
      context[:profile_user]
    end

    def own_profile?
      user.present? && user == profile_user
    end

    def profile_display_name
      profile_user.display_name
    end

    def recent_achievements
      @recent_achievements ||= begin
        records = User::Achievement
          .where(user: profile_user)
          .order(earned_at: :desc)
          .limit(5)

        records.filter_map do |record|
          achievement = record.achievement
          next unless achievement

          { achievement: achievement, earned_at: record.earned_at }
        end
      end
    end

    def earned_count
      @earned_count ||= profile_user.achievements.count
    end

    def total_count
      @total_count ||= ::Achievement.countable_for_user(profile_user).size
    end

    def render?
      profile_user.present? && Flipper.enabled?(:week_2_release, user)
    end
  end
end
