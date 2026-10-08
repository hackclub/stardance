require "test_helper"

class DiscoverRailWidgetsTest < ActiveSupport::TestCase
  test "a group of widgets is shuffled within its spot in the rail" do
    controller = Class.new(ApplicationController) do
      discover_rail_widgets :streak, [ :terra_portal, :forge_promo, :crescent_promo ], :raffle
    end
    rails = Array.new(30) { controller.new.discover_rail_widgets }

    rails.each do |rail|
      assert_equal :streak, rail.first
      assert_equal :raffle, rail.last
      assert_equal %i[crescent_promo forge_promo terra_portal], rail[1..3].sort
    end
    assert_operator rails.uniq.size, :>, 1, "the group came out in the same order every time"
  end
end
