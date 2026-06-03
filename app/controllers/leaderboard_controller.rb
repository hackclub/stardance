class LeaderboardController < ApplicationController
  def index
    scope = User.discoverable
                .joins(:preference)
                .where(user_preferences: { leaderboard_optin: true }, banned: false)

    @current_users = scope.sort_by { |u| -u.cached_balance }.first(50)
    @all_time_users = scope.sort_by { |u| -u.cached_total_earned }.first(50)
    @total_count = scope.count
  end
end
