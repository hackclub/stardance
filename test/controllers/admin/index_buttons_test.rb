require "test_helper"

class Admin::IndexButtonsTest < ActionDispatch::IntegrationTest
  include UserFactory

  test "the dashboard links shop managers to the sticky streak reward editor" do
    manager = create_user(slack_id: "U_IDX_SHOP", display_name: "idx_shop")
    manager.grant_role!(:shop_manager)
    sign_in manager

    get admin_root_path

    assert_response :success
    assert_select "a[href=?]:not(.disabled)", admin_shop_sticky_streak_rewards_path
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
