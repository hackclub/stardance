require "test_helper"

class RaffleEndedDashboardTest < ActionDispatch::IntegrationTest
  include RaffleEndedHelpers

  setup { host! "raffle.example.com" }

  test "an entrant's dashboard shows only the ended notice in place of the raffle UI" do
    get "/dev_login"
    follow_redirect!

    assert_response :success
    assert_select ".raffle-dash"
    assert_select ".raffle-ended-notice em", text: "The AMD GPU raffle event has ended."
    assert_select ".raffle-claim, .raffle-hca-notice, .raffle-share, .raffle-fraud-notice", count: 0
    assert_select "button", text: "Claim free entry", count: 0
    assert_select ".raffle-weekpick, .raffle-card, .raffle-cols, .raffle-deck, .raffle-odds", count: 0
    assert_select "h2", text: /Leaderboard|Verified|Pending|Questions/, count: 0
    assert_no_match(/RX 9060|every week/, response.body)
  end

  test "the signed-out raffle page shows only the ended notice" do
    get "/"

    assert_response :success
    assert_select ".raffle-landing .raffle-ended-notice em", text: "The AMD GPU raffle event has ended."
    assert_select ".raffle-landing__auth, .raffle-card, .raffle-deck", count: 0
    assert_select "h2", text: /Leaderboard|Questions/, count: 0
    assert_no_match(/RX 9060|every week|Sign in with GitHub/, response.body)
  end

  test "turning the ended switch off brings the hidden raffle UI back" do
    with_raffle_ended(false) do
      get "/dev_login"
      follow_redirect!
      assert_response :success
      assert_select ".raffle-ended-notice", count: 0
      assert_select ".raffle-header__sub", text: /RX 9060 XT every week/
      assert_select ".raffle-share__label", text: "Your referral link"
      assert_select ".raffle-fraud-notice", text: /Heads up/
      assert_select "h2", text: /Leaderboard/
      assert_select ".raffle-card__title", text: /Verified/
      assert_select ".raffle-card__title", text: /Pending/
      assert_select "h2", text: /Questions/

      delete "/logout"
      get "/"
      assert_response :success
      assert_select ".raffle-landing__auth"
      assert_match(/RX 9060 XT every week for 16 weeks/, response.body)
    end
  end
end
