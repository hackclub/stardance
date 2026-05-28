require "test_helper"

class ProjectShopTutorialRequirementTest < ActiveSupport::TestCase
  setup do
    @owner = create_user(slack_id: "U_SHIP_OWNER", display_name: "shipowner")
    @project = Project.create!(title: "shippable", description: "d")
    @project.memberships.create!(user: @owner, role: :owner)
  end

  test "shop_tutorial requirement fails when the owner hasn't finished the walkthrough" do
    req = @project.shipping_requirements.find { |r| r[:key] == :shop_tutorial }
    assert req, "shop_tutorial requirement should be listed"
    refute req[:passed]
  end

  test "shop_tutorial requirement passes once the owner completes the walkthrough" do
    @owner.mark_shop_tutorial_completed!

    req = @project.shipping_requirements.find { |r| r[:key] == :shop_tutorial }
    assert req[:passed]
  end
end
