require "test_helper"

class DiscoverRail::SavepointPromoWidgetTest < ViewComponent::TestCase
  setup do
    Flipper.enable(:platform_ads)
    Flipper.enable(:"savepoint-promo")
  end

  teardown do
    Flipper.disable(:"savepoint-promo")
    Flipper.disable(:platform_ads)
  end

  test "registers under the savepoint_promo slug" do
    assert_equal DiscoverRail::SavepointPromoWidget, DiscoverRail::BaseWidget.registry[:savepoint_promo]
  end

  test "renders the rolling prize card as a tracked link to save point" do
    render_inline(DiscoverRail::SavepointPromoWidget.new)

    assert_selector "section.savepoint-promo[data-controller='savepoint-promo']"
    assert_selector "a.savepoint-promo__card[href='/promos/savepoint'][aria-label='Save Point: finish your game, get a keyboard, controller, mouse or Steam card']" do
      assert_selector ".savepoint-promo__track span", text: "Steam card"
      assert_selector "img.savepoint-promo__sticker", count: 4
      assert_selector "img.savepoint-promo__sticker--active", count: 1
      assert_selector "img.savepoint-promo__logo"
    end
  end

  test "is hidden while the savepoint promo flag is off" do
    Flipper.disable(:"savepoint-promo")

    render_inline(DiscoverRail::SavepointPromoWidget.new)

    assert_no_selector ".savepoint-promo"
  end

  test "is hidden when the user turned platform ads off" do
    Flipper.disable(:platform_ads)

    render_inline(DiscoverRail::SavepointPromoWidget.new)

    assert_no_selector ".savepoint-promo"
  end

  test "is hidden once save point has ended" do
    travel_to DiscoverRail::SavepointPromoWidget::ENDS_AT - 1.minute do
      render_inline(DiscoverRail::SavepointPromoWidget.new)
      assert_selector ".savepoint-promo"
    end

    travel_to DiscoverRail::SavepointPromoWidget::ENDS_AT do
      render_inline(DiscoverRail::SavepointPromoWidget.new)
      assert_no_selector ".savepoint-promo"
    end
  end

  test "supports actor-targeted rollout" do
    Flipper.disable(:"savepoint-promo")
    Flipper.enable_actor(:"savepoint-promo", users(:one))

    render_inline(DiscoverRail::SavepointPromoWidget.new(user: users(:one)))
    assert_selector ".savepoint-promo"

    render_inline(DiscoverRail::SavepointPromoWidget.new(user: users(:two)))
    assert_no_selector ".savepoint-promo"
  end
end
