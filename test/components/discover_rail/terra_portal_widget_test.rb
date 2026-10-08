require "test_helper"

class DiscoverRail::TerraPortalWidgetTest < ViewComponent::TestCase
  setup { Flipper.enable(:platform_ads) }
  teardown { Flipper.disable(:platform_ads) }

  test "registers under the terra_portal slug" do
    assert_equal DiscoverRail::TerraPortalWidget, DiscoverRail::BaseWidget.registry[:terra_portal]
  end

  test "renders the portal as a plain link to Terra" do
    render_inline(DiscoverRail::TerraPortalWidget.new)

    assert_selector "section.terra-portal[data-controller='terra-portal']"
    assert_selector "a.terra-portal__stage[href='#{DiscoverRail::TerraPortalWidget::URL}']" do
      assert_selector "img.terra-portal__view"
      assert_selector "canvas.terra-portal__canvas"
    end
  end

  test "all program rail ads are hidden while platform ads are off" do
    Flipper.disable(:platform_ads)

    [ DiscoverRail::TerraPortalWidget, DiscoverRail::ForgePromoWidget ].each do |widget|
      render_inline(widget.new)
      assert_no_selector "section"
    end
  end

  test "all program rail ads respect an account opt-out without affecting other users" do
    user = users(:one)
    other_user = users(:two)
    user.preference.update!(platform_ads_enabled: false)

    [ DiscoverRail::TerraPortalWidget, DiscoverRail::ForgePromoWidget ].each do |widget|
      render_inline(widget.new(user: user))
      assert_no_selector "section"

      render_inline(widget.new(user: other_user))
      assert_selector "section"
    end
  end

  test "program rail ads support actor-targeted rollout" do
    Flipper.disable(:platform_ads)
    Flipper.enable_actor(:platform_ads, users(:one))

    render_inline(DiscoverRail::TerraPortalWidget.new(user: users(:one)))
    assert_selector ".terra-portal"

    render_inline(DiscoverRail::TerraPortalWidget.new(user: users(:two)))
    assert_no_selector ".terra-portal"
  end
end
