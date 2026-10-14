require "test_helper"

class ProjectMissionReviewRequirementTest < ActiveSupport::TestCase
  setup do
    @owner = create_user(slack_id: "U_MISSION_REVIEW", display_name: "missionreviewowner")
    @project = Project.create!(title: "mission review project", description: "d")
    @project.memberships.create!(user: @owner, role: :owner)
    @mission = create_mission
    @project.mission_attachments.create!(mission: @mission)
  end

  def mission_review_requirement
    @project.shipping_requirements.find { |r| r[:key] == :mission_review }
  end

  test "requirement passes when the project has never shipped to a mission" do
    assert mission_review_requirement[:passed]
  end

  test "requirement passes while the submission is still awaiting certification" do
    ship_to_mission!(@project, @owner, @mission)

    assert mission_review_requirement[:passed],
      "certification is gated separately, so an uncertified ship must not report a mission block"
  end

  test "requirement blocks shipping while the mission review is pending" do
    ship_to_mission!(@project, @owner, @mission, status: "pending")

    refute mission_review_requirement[:passed]
    assert_equal "Wait for your mission submission to be reviewed before shipping again",
                 @project.mission_review_blocker_message
  end

  test "requirement blocks shipping while the mission review is rejected" do
    ship_to_mission!(@project, @owner, @mission, status: "rejected")

    refute mission_review_requirement[:passed]
    assert_equal "Your mission submission was returned. Address the feedback and request a re-review",
                 @project.mission_review_blocker_message
  end

  test "requirement passes once the mission review is approved" do
    ship_to_mission!(@project, @owner, @mission, status: "approved")

    assert mission_review_requirement[:passed]
    assert_nil @project.mission_review_blocker_message
  end

  test "a certifier-rejected ship is left to the re-certification flow" do
    submission = ship_to_mission!(@project, @owner, @mission, status: "rejected")
    submission.ship_event.update!(certification_status: "rejected")

    assert mission_review_requirement[:passed]
  end

  test "detaching the mission clears the rejected submission off the latest ship" do
    submission = ship_to_mission!(@project, @owner, @mission, status: "rejected")

    @project.detach_mission!

    assert submission.reload.deleted?
    assert_nil @project.last_ship_event.reload.mission_submission
    assert mission_review_requirement[:passed]
  end

  test "detaching leaves a pending submission alone" do
    submission = ship_to_mission!(@project, @owner, @mission, status: "pending")

    @project.detach_mission!

    refute submission.reload.deleted?
    refute mission_review_requirement[:passed]
  end

  test "a detached fixed-prize ship does not block the next ship on its missing payout" do
    submission = ship_to_mission!(@project, @owner, @mission, status: "rejected")
    submission.update!(payout_path: "static_prize")
    submission.ship_event.update!(certification_status: "approved")

    @project.detach_mission!

    assert @project.shipping_requirements.find { |r| r[:key] == :payout }[:passed],
      "a detached fixed-prize ship never enters the rating pool, so it can't wait on a payout forever"
  end

  test "a fixed-prize submission cannot skip the review gate" do
    submission = ship_to_mission!(@project, @owner, @mission, status: "pending")
    submission.update!(payout_path: "static_prize")
    submission.ship_event.update!(certification_status: "approved")

    assert @project.shipping_requirements.find { |r| r[:key] == :payout }[:passed],
      "fixed-prize ships bypass the payout gate, which is why the mission gate has to hold"
    refute mission_review_requirement[:passed]
    refute @project.shippable?
  end
end
