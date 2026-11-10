require "test_helper"

class Admin::Users::ShopUnlocksControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  setup do
    @admin = create_user(slack_id: "U_SU_ADMIN", display_name: "su_admin")
    @admin.grant_role!(:admin)
    @user = create_user(slack_id: "U_SU_USER", display_name: "su_user")
  end

  teardown do
    Flipper.disable(:shop_unlocked)
  end

  test "an admin unlocks and relocks the shop with an audit trail" do
    sign_in @admin

    post admin_user_shop_unlock_path(@user)

    assert_redirected_to admin_user_path(@user)
    assert Flipper.enabled?(:shop_unlocked, @user)
    assert PaperTrail::Version.exists?(item_type: "User", item_id: @user.id, event: "shop_unlocked", whodunnit: @admin.id.to_s)

    delete admin_user_shop_unlock_path(@user)

    assert_not Flipper.enabled?(:shop_unlocked, @user)
    assert PaperTrail::Version.exists?(item_type: "User", item_id: @user.id, event: "shop_relocked", whodunnit: @admin.id.to_s)
  end

  test "fraud staff can't unlock the shop" do
    fraud = create_user(slack_id: "U_SU_FRAUD", display_name: "su_fraud")
    fraud.grant_role!(:fraud_dept)
    sign_in fraud

    post admin_user_shop_unlock_path(@user)

    assert_not Flipper.enabled?(:shop_unlocked, @user)
  end
end
