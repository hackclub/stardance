require "test_helper"

class MyResourcesTest < ActionDispatch::IntegrationTest
  test "update_settings stores preference separately from user account fields" do
    user = users(:one)
    sign_in user

    patch my_settings_path, params: {
      hcb_email: "grants@example.test",
      send_votes_to_slack: "1",
      leaderboard_optin: "1",
      search_engine_indexing_off: "1"
    }

    assert_redirected_to root_path
    assert_equal "grants@example.test", user.reload.hcb_email

    preference = user.preference.reload
    assert preference.send_votes_to_slack
    assert preference.leaderboard_optin
    assert preference.search_engine_indexing_off
  end

  test "dismissal resource records dismissed thing" do
    user = users(:one)
    user.update_columns(things_dismissed: [])
    sign_in user

    post my_dismissals_path, params: { thing_name: "willsbuilds_banner" }

    assert_response :success
    assert user.reload.has_dismissed?("willsbuilds_banner")
  end

  test "particle preference can be disabled and enabled without changing another user" do
    user = users(:one)
    other_preference = users(:two).preference
    other_preference.update!(particle_effects_enabled: true)
    sign_in user

    patch my_settings_path, params: { particle_effects_enabled: "0" }
    assert_redirected_to root_path
    assert_not user.preference.reload.particle_effects_enabled
    assert other_preference.reload.particle_effects_enabled

    patch my_settings_path, params: { hcb_email: "grants@example.test" }
    assert_not user.preference.reload.particle_effects_enabled, "unrelated updates preserve the preference"

    patch my_settings_path, params: { particle_effects_enabled: "1" }
    assert_redirected_to root_path
    assert user.preference.reload.particle_effects_enabled
  end
end
