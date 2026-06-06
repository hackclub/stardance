class LeaderboardController < ApplicationController
  def index
    scope = User.on_leaderboard

    @total_count = scope.count
    @current_users = scope.top_by_balance
    @all_time_users = scope.top_by_total_earned

    if current_user
      @current_user_rank = scope.balance_rank_for(current_user)
      @all_time_user_rank = scope.total_earned_rank_for(current_user)
    end
  end
end
