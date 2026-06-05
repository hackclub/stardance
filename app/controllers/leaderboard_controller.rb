class LeaderboardController < ApplicationController
  def index
    @scope = User.discoverable
                .joins(:preference)
                .where(user_preferences: { leaderboard_optin: true }, banned: false)

    @current_users = @scope.sort_by { |u| -u.cached_balance }.first(10)
    @all_time_users = @scope.sort_by { |u| -u.cached_total_earned }.first(10)
    @total_count = @scope.count

    if current_user
      @current_user_rank = calculate_rank(:cached_balance)
      @all_time_user_rank = calculate_rank(:cached_total_earned)
    end
  end

  private

  def calculate_rank(method)
    all_sorted = @scope.to_a.sort_by { |u| -u.public_send(method) }
    idx = all_sorted.index { |u| u.id == current_user.id }
    return idx + 1 if idx

    user_score = current_user.public_send(method)
    all_sorted.count { |u| u.public_send(method) > user_score } + 1
  end
end
