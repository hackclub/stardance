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
require "test_helper"

class User::PreferenceTest < ActiveSupport::TestCase
  test "new users get default preference" do
    user = User.create!(slack_id: "U_PREF_DEFAULTS", display_name: "pref-user", email: "pref@example.test")

    assert user.preference
    assert_not user.preference.send_votes_to_slack
    assert_not user.preference.leaderboard_optin
    assert_not user.preference.search_engine_indexing_off
  end

  test "each user can only have one preference record" do
    user = users(:one)
    duplicate = User::Preference.new(user: user)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end
end
