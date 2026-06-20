# frozen_string_literal: true

class AchievementsController < ApplicationController
  def index
    authorize :achievement
    head :not_found and return unless Flipper.enabled?(:week_2_release, current_user)

    Achievement.all.each { |a| grant_achievement!(a.slug) if a.earned_by?(current_user) }

    user_achievements_by_slug = current_user.achievements.index_by(&:achievement_slug)

    @achievements = Achievement.all.map do |achievement|
      user_achievement = user_achievements_by_slug[achievement.slug.to_s]
      {
        achievement: achievement,
        earned: user_achievement.present?,
        earned_at: user_achievement&.earned_at,
        progress: achievement.progress_for(current_user)
      }
    end

    countable = Achievement.countable_for_user(current_user)
    earned_countable = countable.count { |a| user_achievements_by_slug[a.slug.to_s].present? }
    @achievement_stats = {
      earned: earned_countable,
      total: countable.count
    }
  end
end
