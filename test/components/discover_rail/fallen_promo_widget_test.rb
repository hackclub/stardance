require "test_helper"

class DiscoverRail::FallenPromoWidgetTest < ViewComponent::TestCase
  setup do
    Flipper.enable(:platform_ads)
    Flipper.enable(:"fallen-promo")
  end

  teardown do
    Flipper.disable(:"fallen-promo")
    Flipper.disable(:platform_ads)
  end

  test "registers under the fallen_promo slug" do
    assert_equal DiscoverRail::FallenPromoWidget, DiscoverRail::BaseWidget.registry[:fallen_promo]
  end

  test "renders the logo, lulu and sami, and the copy as one tracked link to fallen" do
    render_inline(DiscoverRail::FallenPromoWidget.new)

    assert_selector "section.fallen-promo[data-controller~='fallen-launch'][data-fallen-launch-url-value='#{DiscoverRail::FallenPromoWidget::URL}'] " \
                    "a.fallen-promo__card[href='/promos/fallen'][data-action='fallen-launch#launch']" do
      assert_selector "img.fallen-promo__logo[alt='Hack Club Fallen']"
      assert_selector "img.fallen-promo__character", count: 2
      assert_selector ".fallen-promo__date", text: DiscoverRail::FallenPromoWidget::DATES
      assert_selector ".fallen-promo__tagline", text: "Build a hardware project"
    end
  end

  test "is hidden while platform ads are off" do
    Flipper.disable(:platform_ads)

    render_inline(DiscoverRail::FallenPromoWidget.new)
    assert_no_selector "section"
  end

  test "is hidden while the fallen promo flag is off" do
    Flipper.disable(:"fallen-promo")

    render_inline(DiscoverRail::FallenPromoWidget.new)
    assert_no_selector "section"
  end
end
