class LeaderboardController < ApplicationController
  def index
   scope = User
          .joins(:hack_club_identity)
          .joins(:preference)
          .left_joins(:ledger_entries)
          .where(user_preferences: { leaderboard_optin: true }, banned: false)
          .group("users.id")
          .select("users.*, COALESCE(SUM(ledger_entries.amount), 0) AS leaderboard_balance")
          .order(Arel.sql("COALESCE(SUM(ledger_entries.amount), 0) DESC"))

    @pagy, @users = pagy(:offset, scope, limit: 10)
  end
end
