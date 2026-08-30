class StreakSyncJob < ApplicationJob
  queue_as :literally_whenever

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    StreakActivity.sync_for_user!(user)
  end
end
