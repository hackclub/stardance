# == Schema Information
#
# Table name: user_preferences
#
#  id                                       :bigint           not null, primary key
#  leaderboard_optin                        :boolean          default(FALSE), not null
#  search_engine_indexing_off               :boolean          default(FALSE), not null
#  send_notifications_for_followed_projects :boolean          default(TRUE), not null
#  send_notifications_for_followed_users    :boolean          default(TRUE), not null
#  send_notifications_for_new_comments      :boolean          default(TRUE), not null
#  send_notifications_for_new_followers     :boolean          default(TRUE), not null
#  send_votes_to_slack                      :boolean          default(FALSE), not null
#  stardust_balance_notifications           :boolean          default(FALSE), not null
#  streak_slack_status_enabled              :boolean          default(TRUE), not null
#  created_at                               :datetime         not null
#  updated_at                               :datetime         not null
#  user_id                                  :bigint           not null
#
# Indexes
#
#  index_user_preferences_on_leaderboard_optin  (leaderboard_optin)
#  index_user_preferences_on_user_id            (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class User::Preference < ApplicationRecord
  belongs_to :user

  validates :user_id, uniqueness: true
end
