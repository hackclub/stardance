require "test_helper"

class Feed::WrongToolPromoComponentTest < ViewComponent::TestCase
  setup do
    Flipper.enable(:platform_ads)
    Flipper.enable(:wrong_tool_promo)
  end

  teardown do
    Flipper.disable(:wrong_tool_promo)
    Flipper.disable(:platform_ads)
  end

  test "a sheet to fly the rocket through, and a way to wrong tool" do
    travel_to Feed::WrongToolPromoComponent::ENDS_ON do
      render_inline Feed::WrongToolPromoComponent.new
    end

    columns = Feed::WrongToolPromoComponent::COLUMNS.size
    assert_selector ".wrong-tool-promo[data-wrong-tool-sheet-columns-value='#{columns}']"
    assert_selector ".wrong-tool-promo__cell", count: columns * Feed::WrongToolPromoComponent::ROWS
    assert_selector "a.wrong-tool-promo__cta[href='/promos/wrong_tool']", text: "Start building"
    assert_selector "button[aria-label='Hide this']"
  end

  test "gone once wrong tool's over" do
    travel_to Feed::WrongToolPromoComponent::ENDS_ON + 1 do
      render_inline Feed::WrongToolPromoComponent.new
    end

    assert_no_selector ".wrong-tool-promo"
  end

  test "hidden while the flag is off" do
    Flipper.disable(:wrong_tool_promo)

    travel_to Feed::WrongToolPromoComponent::ENDS_ON do
      render_inline Feed::WrongToolPromoComponent.new
    end

    assert_no_selector ".wrong-tool-promo"
  end

  test "hidden while platform ads are off" do
    Flipper.disable(:platform_ads)

    travel_to Feed::WrongToolPromoComponent::ENDS_ON do
      render_inline Feed::WrongToolPromoComponent.new
    end

    assert_no_selector ".wrong-tool-promo"
  end

  test "hidden when the signed-in user opts out" do
    user = users(:one)
    user.preference.update!(platform_ads_enabled: false)

    with_controller_class ApplicationController do
      vc_test_controller.stub(:current_user, user) do
        travel_to Feed::WrongToolPromoComponent::ENDS_ON do
          render_inline Feed::WrongToolPromoComponent.new
        end
      end
    end

    assert_no_selector ".wrong-tool-promo"
  end
end
