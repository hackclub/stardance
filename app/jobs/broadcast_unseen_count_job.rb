class BroadcastUnseenCountJob < ApplicationJob
  queue_as :latency_5m

  discard_on ActiveJob::DeserializationError

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    NotificationsChannel.broadcast_unseen_count(user)
  end
end
