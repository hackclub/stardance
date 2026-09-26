# Daily sweep that grants the rng_winner achievement to every day's leaderboard
# topper (see DailyRoll.grant_winner_achievements! — the achievement is also
# granted lazily whenever a qualifying user visits /achievements, but that
# alone would silently skip anyone who wins and never happens to load that
# page) and sends the (one-time-ever, per user) RngWinner notification to
# anyone holding it who hasn't been notified yet.
class RngWinnerNotificationJob < ApplicationJob
  queue_as :default

  # config/recurring.yml declares this job as concurrency: 1, but solid_queue
  # doesn't actually read that key for recurring tasks — this is what
  # enforces it, so an overlapping manual/retry run can't double-notify.
  limits_concurrency to: 1, key: "rng_winner_notification", duration: 30.minutes

  def perform
    DailyRoll.grant_winner_achievements!

    User::Achievement.where(achievement_slug: "rng_winner").includes(:user).find_each do |user_achievement|
      user = user_achievement.user
      next if Notifications::RngWinner.exists?(recipient: user)

      Notifications::RngWinner.notify(recipient: user, record: DailyRoll.first_win(user))
    end
  end
end
