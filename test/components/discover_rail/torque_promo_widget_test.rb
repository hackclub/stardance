require "test_helper"

class DiscoverRail::TorquePromoWidgetTest < ViewComponent::TestCase
  setup do
    Flipper.enable(:platform_ads)
    Flipper.enable(:"torque-promo")
  end

  teardown do
    Flipper.disable(:"torque-promo")
    Flipper.disable(:platform_ads)
  end

  test "registers under the torque_promo slug" do
    assert_equal DiscoverRail::TorquePromoWidget, DiscoverRail::BaseWidget.registry[:torque_promo]
  end

  test "renders the card as a tracked link to torque" do
    render_inline(DiscoverRail::TorquePromoWidget.new)

    assert_selector "section.torque-promo a.torque-promo__card[href='/promos/torque']" do
      assert_selector "img.torque-promo__wordmark[alt='Torque']"
      assert_selector ".torque-promo__scene img", count: 2
      assert_selector ".torque-promo__pitch", text: "Build anything with a motor and we'll fund the parts."
      assert_selector ".torque-promo__button", text: "Start building"
    end
  end

  test "is hidden while the torque promo flag is off" do
    Flipper.disable(:"torque-promo")

    render_inline(DiscoverRail::TorquePromoWidget.new)

    assert_no_selector ".torque-promo"
  end

  test "is hidden while platform ads are off" do
    Flipper.disable(:platform_ads)

    render_inline(DiscoverRail::TorquePromoWidget.new)

    assert_no_selector ".torque-promo"
  end
end
