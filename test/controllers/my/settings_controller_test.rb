require "test_helper"

class My::SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "program ads default on for new accounts" do
    user = create_user(slack_id: "U_AD_DEFAULT", display_name: "adsdefault")

    assert user.preference.platform_ads_enabled?
  end

  test "settings can persistently disable and re-enable program ads for the current user" do
    patch my_settings_path, params: { platform_ads_enabled: "0", user_id: users(:two).id }

    assert_response :redirect
    assert_not @user.preference.reload.platform_ads_enabled?
    assert users(:two).preference.reload.platform_ads_enabled?

    patch my_settings_path, params: { platform_ads_enabled: "1" }

    assert_response :redirect
    assert @user.preference.reload.platform_ads_enabled?
  end

  test "omitting the program ad setting preserves an opt-out" do
    @user.preference.update!(platform_ads_enabled: false)

    patch my_settings_path, params: { particle_effects_enabled: "0" }

    assert_response :redirect
    assert_not @user.preference.reload.platform_ads_enabled?
  end

  test "settings display the saved program ad preference" do
    get home_path

    assert_select "input[type=hidden][name=platform_ads_enabled][value='0']"
    assert_select "input[type=checkbox][name=platform_ads_enabled][checked]"

    @user.preference.update!(platform_ads_enabled: false)
    get home_path

    assert_select "input[type=checkbox][name=platform_ads_enabled]"
    assert_select "input[type=checkbox][name=platform_ads_enabled][checked]", count: 0
  end
end
