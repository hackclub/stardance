class Api::V1::Users::AchievementsController < Api::BaseController
  include ApiAuthenticatable

  def index
    @user = User.find(params[:user_id])
    user_achievements = @user.achievements.to_a
    earned_slugs = user_achievements.map(&:achievement_slug).to_set

    @achievements = Achievement.all.filter_map do |achievement|
      earned = earned_slugs.include?(achievement.slug.to_s)
      next unless earned

      ua = user_achievements.find { |a| a.achievement_slug == achievement.slug.to_s }
      { achievement: achievement, earned_at: ua.earned_at }
    end
  end
end
