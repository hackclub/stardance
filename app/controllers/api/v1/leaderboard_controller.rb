class Api::V1::LeaderboardController < Api::BaseController
  include ApiAuthenticatable

  def index
    scope = User.on_leaderboard
    @by_balance = scope.top_by_balance(100)
    @by_total_earned = scope.top_by_total_earned(100)
    @balance_rank = User.balance_rank_for(current_api_user)
    @total_earned_rank = User.total_earned_rank_for(current_api_user)
  end
end
