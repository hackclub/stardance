# Refreshes a user's Hackatime stats off the request path: records any new
# Hackatime project names and auto-bans users who are banned on Hackatime.
class User::SyncHackatimeDataJob < ApplicationJob
  queue_as :latency_10s

  def perform(user_id)
    User.find_by(id: user_id)&.try_sync_hackatime_data!
  end
end
