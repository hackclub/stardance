require "test_helper"

class Certification::ShipMissionCollapseTest < ActiveSupport::TestCase
  setup do
    @owner = create_user(slack_id: "U_HWC_OWNER", display_name: "hwowner")
    @reviewer = create_user(slack_id: "U_HWC_REV", display_name: "hwrev")
  end

  test "approving a hardware mission ship cert also approves the mission submission and grants rewards" do
    project, submission = ship_to_hardware_mission(achievement: true)
    cert = project.ship_reviews.create!(status: :pending, post_ship_event: submission.ship_event)

    cert.update!(status: :approved, reviewer: @reviewer)

    assert submission.reload.approved?, "hardware mission submission should be auto-approved with the ship cert"
    assert_equal @reviewer.id, submission.reviewed_by_id
    assert @owner.achievements.exists?(achievement_slug: submission.mission.achievement_slug),
           "the mission achievement should be granted"
  end

  test "approving a software mission ship cert leaves the submission pending for its own review" do
    project, submission = ship_to_software_mission
    cert = project.ship_reviews.create!(status: :pending, post_ship_event: submission.ship_event)

    cert.update!(status: :approved, reviewer: @reviewer)

    assert submission.reload.pending?, "software mission submission must still await its own approval"
  end

  private

  def ship_to_hardware_mission(achievement: false)
    project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "build")
    project.memberships.create!(user: @owner, role: :owner)
    mission = create_mission
    mission.update!(hardware: true)
    mission.update!(achievement_name: "Done") if achievement
    project.mission_attachments.create!(mission: mission)
    [ project, ship_to_mission!(project, @owner, mission) ]
  end

  def ship_to_software_mission
    project = Project.create!(title: "SW #{SecureRandom.hex(4)}")
    project.memberships.create!(user: @owner, role: :owner)
    mission = create_mission
    project.mission_attachments.create!(mission: mission)
    [ project, ship_to_mission!(project, @owner, mission) ]
  end
end
