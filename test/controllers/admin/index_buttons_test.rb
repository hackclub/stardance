require "test_helper"

class Admin::IndexButtonsTest < ActionDispatch::IntegrationTest
  include UserFactory

  test "dashboard links the jim takeover next to mega dashboard without embedding event metrics" do
    sign_in users(:tongyu)
    BukuX3::Assignment.stub(:discovered_counts, -> { flunk "metrics belong on their own dashboard" }) do
      get admin_root_path
    end
    assert_response :success
    assert_select "a[href=?] + a[href=?]", admin_mega_dashboard_path, admin_jim_takeover_path, text: "the jim takeover"
    assert_select ".admin-dashboard__metric, .admin-dashboard__event-controls", count: 0
  end

  test "non-staff cannot access role discovery metrics" do
    sign_in users(:one)
    BukuX3::Assignment.stub(:discovered_counts, -> { flunk "must authorize before querying counts" }) do
      get admin_root_path
    end
    assert_redirected_to home_path
    assert_select ".admin-dashboard__metric", count: 0
  end

  test "the dashboard links shop managers to the sticky streak reward editor" do
    manager = create_user(slack_id: "U_IDX_SHOP", display_name: "idx_shop")
    manager.grant_role!(:shop_manager)
    sign_in manager

    get admin_root_path

    assert_response :success
    assert_select "a[href=?]:not(.disabled)", admin_shop_sticky_streak_rewards_path
  end

  test "the dashboard links the fraud squad to the per-person queue" do
    squaddie = create_user(slack_id: "U_IDX_FRAUD", display_name: "idx_fraud")
    squaddie.grant_role!(:fraud_fraud_squad_squad)
    sign_in squaddie

    get admin_root_path

    assert_response :success
    assert_select "a[href=?]:not(.disabled)", admin_fraud_subjects_path
  end

  test "the per-person queue link is disabled without fraud access" do
    other = create_user(slack_id: "U_IDX_NOFRAUD", display_name: "idx_nofraud")
    other.grant_role!(:workshop_manager)
    sign_in other

    get admin_root_path

    assert_response :success
    assert_select "a.disabled[href=?]", admin_fraud_subjects_path
  end

  test "the link is disabled for admins without shop access" do
    other = create_user(slack_id: "U_IDX_WS", display_name: "idx_ws")
    other.grant_role!(:workshop_manager)
    sign_in other

    get admin_root_path

    assert_response :success
    assert_select "a.disabled[href=?]", admin_shop_sticky_streak_rewards_path
  end
end
