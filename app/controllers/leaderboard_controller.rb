class LeaderboardController < ApplicationController
  def index
    scope = User.where(leaderboard_optin: true, banned: false)

    sorted_users = scope.sort_by { |u| -u.cached_balance }
    @pagy, @users = pagy(:offset, sorted_users, limit: 10)
  end
end
