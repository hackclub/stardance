require "test_helper"

class GpuPromoHiddenTest < ActionDispatch::IntegrationTest
  include RaffleEndedHelpers

  test "the landing page drops the GPU from its sign-up line and prizes" do
    get root_path

    assert_response :success
    assert_select ".hero__subhead", text: /Sign up to get free Stardance stickers!/
    assert_select ".prizes__item--gpu, .prizes__label--gpu", count: 0
    assert_select ".hero__subhead a", text: "19 or older?", count: 0
    assert_no_match(/AMD GPU every week|RX 9060/, response.body)

    with_raffle_ended(false) { get root_path }
    assert_select ".hero__subhead", text: /AMD GPU every week/
    assert_select ".hero__subhead a", text: "19 or older?"
    assert_select ".prizes__item--gpu"
  end

  test "the new project page no longer points to the GPU raffle" do
    sign_in users(:one)

    get new_project_path

    assert_response :success
    assert_select ".project-creation__tagline", text: /plus free stickers/
    assert_select ".project-creation__tagline a", text: "GPU raffle", count: 0

    with_raffle_ended(false) { get new_project_path }
    assert_select ".project-creation__tagline a", text: "GPU raffle"
  end

  test "the home page hides the GPU raffle referral banner" do
    get dev_login_path(id: users(:one).id, raffle_referrer: "someone")

    get home_path
    assert_response :success
    assert_select "#raffle-referral-banner", count: 0
    assert_no_match(/free GPU/, response.body)

    with_raffle_ended(false) { get home_path }
    assert_select "#raffle-referral-banner", text: /closer to a free GPU/
  end
end
