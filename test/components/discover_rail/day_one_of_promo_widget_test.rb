require "test_helper"

class DiscoverRail::DayOneOfPromoWidgetTest < ViewComponent::TestCase
  setup do
    Flipper.enable(:platform_ads)
    Flipper.enable(:"dayoneof-promo")
  end

  teardown do
    Flipper.disable(:"dayoneof-promo")
    Flipper.disable(:platform_ads)
  end

  test "registers under the day_one_of_promo slug" do
    assert_equal DiscoverRail::DayOneOfPromoWidget, DiscoverRail::BaseWidget.registry[:day_one_of_promo]
  end

  test "renders the card with a reel idea shuffler and a link to day one of" do
    render_inline(DiscoverRail::DayOneOfPromoWidget.new)

    assert_selector "section.day-one-of-promo[data-controller='day-one-of-promo']"
    assert_selector "button.day-one-of-promo__idea[data-action='day-one-of-promo#shuffle']" do
      assert_selector "[data-day-one-of-promo-target='idea']", text: DiscoverRail::DayOneOfPromoWidget::IDEAS.first
    end
    assert_selector "a.day-one-of-promo__button[href='/promos/day_one_of']", text: "Start day one"
  end

  test "is hidden while platform ads are off" do
    Flipper.disable(:platform_ads)

    render_inline(DiscoverRail::DayOneOfPromoWidget.new)
    assert_no_selector "section"
  end

  test "is hidden while the dayoneof promo flag is off" do
    Flipper.disable(:"dayoneof-promo")

    render_inline(DiscoverRail::DayOneOfPromoWidget.new)
    assert_no_selector "section"
  end
end
