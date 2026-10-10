require "test_helper"

class DiscoverRail::MipmapPromoWidgetTest < ViewComponent::TestCase
  setup { Flipper.enable(:platform_ads) }
  teardown { Flipper.disable(:platform_ads) }

  test "registers under the mipmap_promo slug" do
    assert_equal DiscoverRail::MipmapPromoWidget, DiscoverRail::BaseWidget.registry[:mipmap_promo]
  end

  test "renders the spinning logo as a tracked link to mipmap" do
    render_inline(DiscoverRail::MipmapPromoWidget.new)

    assert_selector "section.mipmap-promo[data-controller='mipmap-promo']"
    assert_selector "a.mipmap-promo__card[href='/promos/mipmap']" do
      assert_selector "svg.mipmap-promo__logo[data-mipmap-promo-target='logo'] .mipmap-promo__cog", count: 6
      assert_selector ".mipmap-promo__pitch", text: "You make games. But without an engine? Don't worry, we'll teach you."
    end
  end
end
