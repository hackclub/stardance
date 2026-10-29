require "test_helper"

class ProjectShippingClosedRequirementTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(title: "last minute", description: "d")
    @ends_at = Rails.application.config.stardance_ends_at
    Rails.application.config.stardance_ships_close_at = @ends_at
  end

  teardown { Rails.application.config.stardance_ships_close_at = nil }

  test "shipping_open requirement passes before Stardance ends" do
    travel_to(@ends_at - 1.minute) do
      assert requirement[:passed]
    end
  end

  test "shipping_open requirement fails from midnight Saturday ET" do
    travel_to(@ends_at + 1.second) do
      refute requirement[:passed]
      refute @project.shippable?
      assert_equal Project::SHIPPING_CLOSED_MESSAGE, @project.ship_blocker_message
    end
  end

  test "ships never close when no close time is set" do
    Rails.application.config.stardance_ships_close_at = nil

    travel_to(@ends_at + 1.year) do
      assert requirement[:passed]
    end
  end

  private
    def requirement = @project.shipping_requirements.find { |r| r[:key] == :shipping_open }
end
