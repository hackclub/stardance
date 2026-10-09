require "test_helper"

class RaffleEndedDashboardTest < ActionDispatch::IntegrationTest
  setup { host! "raffle.example.com" }

  test "an entrant's dashboard shows only the ended notice in place of the raffle UI" do
    get "/dev_login"
    follow_redirect!

    assert_response :success
    assert_select ".raffle-dash"
    assert_select ".raffle-ended-notice em", text: "The AMD GPU raffle event has ended."
    assert_select ".raffle-claim, .raffle-hca-notice, .raffle-share, .raffle-fraud-notice", count: 0
    assert_select "button", text: "Claim free entry", count: 0
    assert_select ".raffle-weekpick, .raffle-card, .raffle-cols", count: 0
    assert_select "h2", text: /Leaderboard|Verified|Pending/, count: 0
  end

  test "turning the ended switch off brings the hidden raffle UI back" do
    with_raffle_ended(false) do
      get "/dev_login"
      follow_redirect!
    end

    assert_response :success
    assert_select ".raffle-ended-notice", count: 0
    assert_select ".raffle-share__label", text: "Your referral link"
    assert_select ".raffle-fraud-notice", text: /Heads up/
    assert_select "h2", text: /Leaderboard/
    assert_select ".raffle-card__title", text: /Verified/
    assert_select ".raffle-card__title", text: /Pending/
  end

  private

  def with_raffle_ended(value)
    original = Raffle::ApplicationHelper::RAFFLE_ENDED
    Raffle::ApplicationHelper.send(:remove_const, :RAFFLE_ENDED)
    Raffle::ApplicationHelper.const_set(:RAFFLE_ENDED, value)
    yield
  ensure
    Raffle::ApplicationHelper.send(:remove_const, :RAFFLE_ENDED)
    Raffle::ApplicationHelper.const_set(:RAFFLE_ENDED, original)
  end
end
