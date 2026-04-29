# == Schema Information
#
# Table name: users
#
#  id                                      :bigint           not null, primary key
#  banned                                  :boolean          default(FALSE), not null
#  banned_at                               :datetime
#  banned_reason                           :text
#  club_link                               :string
#  club_name                               :string
#  cookie_clicks                           :integer          default(0), not null
#  display_name                            :string
#  email                                   :string
#  enriched_ref                            :string
#  first_name                              :string
#  message_count_14d                       :integer
#  support_message_count_14d               :integer
#  granted_roles                           :string           default([]), not null, is an Array
#  has_gotten_free_stickers                :boolean          default(FALSE)
#  has_pending_achievements                :boolean          default(FALSE), not null
#  hcb_email                               :string
#  internal_notes                          :text
#  last_name                               :string
#  leaderboard_optin                       :boolean          default(FALSE), not null
#  manual_ysws_override                    :boolean
#  metrics_synced_at                       :datetime
#  projects_count                          :integer
#  projects_shipped_count                  :integer
#  ref                                     :string
#  regions                                 :string           default([]), is an Array
#  search_engine_indexing_off              :boolean          default(FALSE), not null
#  send_notifications_for_followed_devlogs :boolean          default(TRUE), not null
#  send_notifications_for_new_comments     :boolean          default(TRUE), not null
#  send_notifications_for_new_followers    :boolean          default(TRUE), not null
#  send_votes_to_slack                     :boolean          default(FALSE), not null
#  session_token                           :string
#  shop_region                             :enum
#  slack_balance_notifications             :boolean          default(FALSE), not null
#  slack_messages_updated_at               :datetime
#  special_effects_enabled                 :boolean          default(TRUE), not null
#  synced_at                               :datetime
#  things_dismissed                        :string           default([]), not null, is an Array
#  tutorial_steps_completed                :string           default([]), is an Array
#  verification_status                     :string           default("needs_submission"), not null
#  vote_anonymously                        :boolean          default(FALSE), not null
#  vote_balance                            :integer          default(0), not null
#  votes_count                             :integer
#  voting_locked                           :boolean          default(FALSE), not null
#  ysws_eligible                           :boolean          default(FALSE), not null
#  created_at                              :datetime         not null
#  updated_at                              :datetime         not null
#  airtable_record_id                      :string
#  slack_id                                :string
#
# Indexes
#
#  index_users_on_airtable_record_id  (airtable_record_id) UNIQUE
#  index_users_on_email               (email)
#  index_users_on_session_token       (session_token) UNIQUE
#  index_users_on_slack_id            (slack_id) UNIQUE
#
require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "grant_email returns hcb_email when present" do
    user = users(:one)
    user.hcb_email = "hcb@example.com"
    assert_equal "hcb@example.com", user.grant_email
  end

  test "grant_email falls back to email when hcb_email is nil" do
    user = users(:one)
    assert user.email.present?, "Fixture user(:one) must have a non-nil email for this test"
    user.hcb_email = nil
    assert_equal user.email, user.grant_email
  end

  test "grant_email falls back to email when hcb_email is blank" do
    user = users(:one)
    user.hcb_email = ""
    assert user.email.present?, "Expected fixture user.email to be present for fallback test"
    assert_equal user.email, user.grant_email
  end

  test "hcb_email validates email format" do
    user = users(:one)
    user.hcb_email = "not-an-email"
    assert_not user.valid?
    assert_includes user.errors[:hcb_email], "is invalid"
    assert_not user.save, "User with invalid hcb_email should not be saved"
  end

  test "hcb_email allows valid email format" do
    user = users(:one)
    user.hcb_email = "valid@example.com"
    assert user.valid?
  end

  test "hcb_email allows blank value" do
    user = users(:one)
    user.hcb_email = ""
    assert user.valid?
  end

  test "hcb_email allows nil value" do
    user = users(:one)
    user.hcb_email = nil
    assert user.valid?
  end
end
