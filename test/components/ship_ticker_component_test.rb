require "test_helper"

class ShipTickerComponentTest < ViewComponent::TestCase
  setup do
    @user = users(:one)
    @ticker = ShipTicker.allocate
    @ticker.instance_variable_set(:@entries, [
      ShipTicker::Ship.new(project_id: 1, project_title: "Rover", author: "ada", hours: 12.5),
      ShipTicker::Purchase.new(shop_item_id: 2, item_name: "Pi", stardust: 1200)
    ])
  end

  teardown { Flipper.disable(ShipTickerComponent::FEATURE_FLAG) }

  test "renders nothing while the flag is off" do
    ShipTicker.stub(:current, -> { flunk "ticker loaded with the flag off" }) do
      render_inline ShipTickerComponent.new(user: @user)
    end

    assert_no_selector ".ship-ticker"
  end

  test "shows ships as ups and purchases as downs once flagged on" do
    Flipper.enable(ShipTickerComponent::FEATURE_FLAG, @user)

    ShipTicker.stub(:current, @ticker) { render_inline ShipTickerComponent.new(user: @user) }

    assert_selector ".ship-ticker__list:not([aria-hidden]) .ship-ticker__item", count: 2
    assert_selector "a.ship-ticker__name[href='/projects/1']", text: "Rover", count: 2
    assert_selector ".ship-ticker__change--up", text: "12.5h"
    assert_selector ".ship-ticker__change--down", text: "1,200"
  end
end
