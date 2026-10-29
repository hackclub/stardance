require "test_helper"

class Finality::RafflesControllerTest < ActionDispatch::IntegrationTest
  setup { Flipper.enable(Finality::RAFFLE_FEATURE_FLAG) }
  teardown { Flipper.disable(Finality::RAFFLE_FEATURE_FLAG) }

  test "guests can see the enabled prize page outside development and sign in to ship" do
    travel_to Finality.window.begin do
      get finality_raffle_path
    end

    assert_response :success
    assert_select ".finality-raffle-page__prize", count: 4
    assert_select ".finality-raffle-page__entry .action-btn[href=?]", root_path
    assert_select ".finality-raffle-page__nav a[href=?]", home_path
  end

  test "signed in shippers see their entry count and can start a project" do
    user = create_user(slack_id: "U_RAFFLE_PAGE", display_name: "raffle_page_user")
    sign_in user

    travel_to Finality.window.begin do
      get finality_raffle_path
    end

    assert_response :success
    assert_select ".finality-raffle-page__entry-title strong", text: "0 entries"
    assert_select ".finality-raffle-page__entry .action-btn[href=?]", new_project_path
  end

  test "the page is unavailable when the flag is disabled" do
    Flipper.disable(Finality::RAFFLE_FEATURE_FLAG)
    sign_in users(:one)
    get finality_raffle_path

    assert_response :forbidden
    assert_select ".finality-raffle-page", count: 0
  end

  test "the closed raffle shows no entry call to action" do
    travel_to Finality.window.end do
      get finality_raffle_path
    end

    assert_response :success
    assert_select ".finality-raffle-page__closed", text: "entries closed"
    assert_select ".finality-raffle-page__entry .action-btn", count: 0
  end
end
