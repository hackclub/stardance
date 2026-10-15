require "test_helper"

class ProjectPayoutRequirementTest < ActiveSupport::TestCase
  setup do
    @owner = create_user(slack_id: "U_PAYOUT_OWNER", display_name: "payoutowner")
    @project = Project.create!(title: "payout project", description: "d")
    @project.memberships.create!(user: @owner, role: :owner)
  end

  def payout_requirement
    @project.shipping_requirements.find { |r| r[:key] == :payout }
  end

  def create_ship_event(status:, payout: nil)
    ship_event = Post::ShipEvent.create!(
      body: "Ship it",
      uploading_attachments: true,
      certification_status: status,
      payout: payout,
      hours_at_ship: 1
    )
    Post.create!(project: @project, user: @owner, postable: ship_event)
    ship_event
  end

  test "payout requirement passes when there is no previous ship" do
    assert payout_requirement[:passed]
  end

  test "payout requirement does not block re-certifying a returned ship" do
    create_ship_event(status: "returned")

    assert payout_requirement[:passed],
      "a ship returned for changes must not be treated as a previous ship awaiting payout"
  end

  test "payout requirement does not block a pending ship" do
    create_ship_event(status: "pending")

    assert payout_requirement[:passed]
  end

  test "payout requirement blocks shipping again while an approved ship awaits payout" do
    create_ship_event(status: "approved", payout: nil)

    refute payout_requirement[:passed]
  end

  test "payout requirement passes once the approved ship has a payout" do
    create_ship_event(status: "approved", payout: 12.5)

    assert payout_requirement[:passed]
  end
end
