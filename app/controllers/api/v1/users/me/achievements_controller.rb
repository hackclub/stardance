class Api::V1::Users::Me::AchievementsController < Api::BaseController
  include ApiAuthenticatable

  def index
    user_achievements = current_api_user.achievements.to_a
    earned_slugs = user_achievements.map(&:achievement_slug).to_set

    @achievements = Achievement.all.filter_map do |achievement|
      earned = earned_slugs.include?(achievement.slug.to_s)
      next unless achievement.shown_to?(current_api_user, earned: earned)

      ua = user_achievements.find { |a| a.achievement_slug == achievement.slug.to_s }
      { achievement: achievement, earned: earned, earned_at: ua&.earned_at, progress: achievement.progress_for(current_api_user) }
    end

    countable = Achievement.countable_for_user(current_api_user)
    @stats = {
      earned: countable.count { |a| earned_slugs.include?(a.slug.to_s) },
      total: countable.count
    }
  end
end
