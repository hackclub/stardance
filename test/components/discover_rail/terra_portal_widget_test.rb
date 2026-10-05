require "test_helper"

class DiscoverRail::TerraPortalWidgetTest < ViewComponent::TestCase
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
end
