require "test_helper"

class DiscoverRail::MipmapPromoWidgetTest < ViewComponent::TestCase
  setup do
    Flipper.enable(:platform_ads)
    Flipper.enable(:"mipmap-promo")
  end

  teardown do
    Flipper.disable(:"mipmap-promo")
    Flipper.disable(:platform_ads)
  end

  test "registers under the mipmap_promo slug" do
    assert_equal DiscoverRail::MipmapPromoWidget, DiscoverRail::BaseWidget.registry[:mipmap_promo]
  end

  test "renders the spinning logo as a tracked link to mipmap" do
    render_inline(DiscoverRail::MipmapPromoWidget.new)

    assert_selector "section.mipmap-promo[data-controller='mipmap-promo'][data-mipmap-promo-url-value='#{DiscoverRail::MipmapPromoWidget::URL}']"
    assert_selector "a.mipmap-promo__card[href='/promos/mipmap']" do
      assert_selector "svg.mipmap-promo__logo[data-mipmap-promo-target='logo'] .mipmap-promo__cog", count: 6
      assert_selector ".mipmap-promo__pitch", text: "You make games. But without an engine? Don't worry, we'll teach you."
    end
  end

  test "is hidden while the mipmap promo flag is off" do
    Flipper.disable(:"mipmap-promo")

    render_inline(DiscoverRail::MipmapPromoWidget.new)

    assert_no_selector ".mipmap-promo"
  end

  test "supports actor-targeted rollout" do
    Flipper.disable(:"mipmap-promo")
    Flipper.enable_actor(:"mipmap-promo", users(:one))

    render_inline(DiscoverRail::MipmapPromoWidget.new(user: users(:one)))
    assert_selector ".mipmap-promo"

    render_inline(DiscoverRail::MipmapPromoWidget.new(user: users(:two)))
    assert_no_selector ".mipmap-promo"
  end
end
