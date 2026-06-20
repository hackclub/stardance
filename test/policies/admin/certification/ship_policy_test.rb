require "test_helper"

class Admin::Certification::ShipPolicyTest < ActiveSupport::TestCase
  setup do
    @reviewer = create_user(slack_id: "U_SHIP_POLICY_REVIEWER", display_name: "ship_policy_reviewer")
    @reviewer.update!(granted_roles: [ "project_certifier" ])
  end

  test "show? is false for a reviewer's own project" do
    ship = ship_for_project(member: @reviewer)

    refute Admin::Certification::ShipPolicy.new(@reviewer, ship).show?
  end

  test "show? is true for another user's project" do
    owner = create_user(slack_id: "U_SHIP_POLICY_OWNER", display_name: "ship_policy_owner")
    ship = ship_for_project(member: owner)

    assert Admin::Certification::ShipPolicy.new(@reviewer, ship).show?
  end

  test "logs? is true for a reviewer" do
    assert Admin::Certification::ShipPolicy.new(@reviewer, Certification::Ship).logs?
  end

  test "logs? is false for a non-reviewer" do
    non_reviewer = create_user(slack_id: "U_SHIP_POLICY_NON_REVIEWER", display_name: "ship_policy_non_reviewer")

    refute Admin::Certification::ShipPolicy.new(non_reviewer, Certification::Ship).logs?
  end

  test "logs? is false without a user" do
    refute Admin::Certification::ShipPolicy.new(nil, Certification::Ship).logs?
  end

  private

  def ship_for_project(member:)
    project = Project.create!(
      title: "Ship policy project #{SecureRandom.hex(4)}",
      description: "Test project"
    )
    Project::Membership.create!(project:, user: member)
    Certification::Ship.create!(project:)
  end
end
