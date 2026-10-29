require "test_helper"

class PollFeatureFlagTest < ActionDispatch::IntegrationTest
  setup { Flipper.disable(:"justin-melena") }
  teardown { Flipper.disable(:"justin-melena") }

  test "disabled poll is hidden and rejects votes even for an onboarded user" do
    sign_in users(:one)

    get home_path
    assert_response :success
    assert_select ".poll-popup", count: 0

    assert_no_difference "PollVote.count" do
      post poll_votes_path, params: { choice: "justin" }
    end
    assert_response :not_found
  end

  test "actor rollout shows the popup and accepts a vote only for the enabled account" do
    Flipper.enable_actor(:"justin-melena", users(:one))
    sign_in users(:one)

    get home_path
    assert_response :success
    assert_select ".poll-popup", count: 1

    assert_difference "PollVote.count", 1 do
      post poll_votes_path, params: { choice: "melena" }
    end
    assert_response :success
    assert_equal "melena", PollVote.find_by!(user: users(:one)).choice

    users(:two).update!(onboarded_at: Time.current)
    sign_in users(:two)
    get home_path
    assert_select ".poll-popup", count: 0
    assert_no_difference "PollVote.count" do
      post poll_votes_path, params: { choice: "justin" }
    end
    assert_response :not_found
  end

  test "enabling the poll still respects dismissal" do
    Flipper.enable(:"justin-melena")
    users(:one).dismiss_thing!(PollVote::DISMISS_THING)
    sign_in users(:one)

    get home_path

    assert_response :success
    assert_select ".poll-popup", count: 0
  end

  test "disabled poll hides admin surfaces without querying poll data" do
    sign_in users(:tongyu)

    PollVote.stub(:tally, -> { flunk "disabled poll must not load results" }) do
      get admin_root_path
      assert_response :success
      assert_select "a[href=?]", admin_poll_results_path, count: 0

      get admin_jim_takeover_path
      assert_response :success
      assert_select "#jimberjake-poll-heading, #poll-results", count: 0

      get admin_poll_results_path
      assert_response :not_found
    end
  end

  test "enabled admin sees poll links and results" do
    Flipper.enable_actor(:"justin-melena", users(:tongyu))
    sign_in users(:tongyu)

    get admin_root_path
    assert_response :success
    assert_select "a[href=?]", admin_poll_results_path, count: 1

    [ admin_jim_takeover_path, admin_poll_results_path ].each do |path|
      get path
      assert_response :success
      assert_select "#poll-results", count: 1
      assert_select ".poll-popup", count: 0
    end
  end

  test "flag does not grant ordinary users access to admin results" do
    Flipper.enable(:"justin-melena")
    sign_in users(:one)

    get admin_poll_results_path

    assert_response :not_found
  end
end
