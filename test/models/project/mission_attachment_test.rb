# == Schema Information
#
# Table name: project_mission_attachments
#
#  id          :bigint           not null, primary key
#  attached_at :datetime         not null
#  deleted_at  :datetime
#  detached_at :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  mission_id  :bigint           not null
#  project_id  :bigint           not null
#
# Indexes
#
#  index_project_mission_attachments_active         (project_id,mission_id) UNIQUE WHERE ((detached_at IS NULL) AND (deleted_at IS NULL))
#  index_project_mission_attachments_on_deleted_at  (deleted_at)
#  index_project_mission_attachments_on_mission_id  (mission_id)
#  index_project_mission_attachments_on_project_id  (project_id)
#  index_project_mission_attachments_one_active     (project_id) UNIQUE WHERE ((detached_at IS NULL) AND (deleted_at IS NULL))
#
# Foreign Keys
#
#  fk_rails_...  (mission_id => missions.id)
#  fk_rails_...  (project_id => projects.id)
#
require "test_helper"

class Project::MissionAttachmentTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "shipper-#{SecureRandom.hex(4)}@example.test",
                         display_name: "shipper-#{SecureRandom.hex(4)}",
                         slack_id: "U#{SecureRandom.hex(8)}")
    @project = Project.create!(title: "Mission Attachment Test")
    @mission = create_mission
  end

  teardown do
    Flipper.disable(:late_mission_attach)
  end

  test "attaches to a draft project" do
    attachment = @project.mission_attachments.create(mission: @mission)

    assert attachment.persisted?
  end

  test "cannot attach a second active mission" do
    @project.mission_attachments.create!(mission: @mission)

    other = @project.mission_attachments.create(mission: create_mission)

    assert_includes other.errors[:base], "Detach the current mission before attaching another"
  end

  test "database enforces one active attachment even when validations are bypassed" do
    @project.mission_attachments.create!(mission: @mission)
    sneaky = @project.mission_attachments.build(mission: create_mission, attached_at: Time.current)

    assert_raises(ActiveRecord::RecordNotUnique) { sneaky.save!(validate: false) }
  end

  test "cannot attach a mission to a shipped project" do
    @project.update!(shipped_at: Time.current)

    attachment = @project.mission_attachments.create(mission: @mission)

    assert_includes attachment.errors[:base], "Can't attach a mission to a project that has already shipped"
  end

  test "can attach a follow-up mission whose prerequisite this project shipped to" do
    @project.mission_attachments.create!(mission: @mission)
    ship_to_mission!(@project, @user, @mission)
    follow_up = create_mission(prerequisite: @mission)

    @project.current_mission_attachment.detach!
    attachment = @project.mission_attachments.create(mission: follow_up)

    assert attachment.persisted?
  end

  test "cannot attach a follow-up mission when the prerequisite ship was rejected" do
    @project.mission_attachments.create!(mission: @mission)
    submission = ship_to_mission!(@project, @user, @mission)
    submission.update_column(:status, "rejected")
    follow_up = create_mission(prerequisite: @mission)

    @project.current_mission_attachment.detach!
    attachment = @project.mission_attachments.create(mission: follow_up)

    assert_includes attachment.errors[:base], "Can't attach a mission to a project that has already shipped"
  end

  test "can re-attach a mission the project shipped to" do
    @project.mission_attachments.create!(mission: @mission)
    ship_to_mission!(@project, @user, @mission)

    @project.current_mission_attachment.detach!
    attachment = @project.mission_attachments.create(mission: @mission)

    assert attachment.persisted?
  end

  test "late-attach flag lets a shipped project with no mission attach one" do
    @project.memberships.create!(user: @user, role: :owner)
    @project.update!(shipped_at: Time.current)
    Flipper.enable_actor(:late_mission_attach, @user)

    attachment = @project.mission_attachments.create(mission: @mission)

    assert attachment.persisted?
  end

  test "late-attach flag only applies to the flagged owner" do
    @project.memberships.create!(user: @user, role: :owner)
    @project.update!(shipped_at: Time.current)
    other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.test",
                         display_name: "other-#{SecureRandom.hex(4)}",
                         slack_id: "U#{SecureRandom.hex(8)}")
    Flipper.enable_actor(:late_mission_attach, other)

    attachment = @project.mission_attachments.create(mission: @mission)

    assert_includes attachment.errors[:base], "Can't attach a mission to a project that has already shipped"
  end

  test "late-attach flag doesn't free a project that already shipped to a mission" do
    @project.memberships.create!(user: @user, role: :owner)
    @project.mission_attachments.create!(mission: @mission)
    ship_to_mission!(@project, @user, @mission)
    Flipper.enable_actor(:late_mission_attach, @user)

    @project.current_mission_attachment.detach!
    attachment = @project.mission_attachments.create(mission: create_mission)

    assert_includes attachment.errors[:base], "Can't attach a mission to a project that has already shipped"
  end

  test "mission picker offers a mission to a flagged shipped project only" do
    @project.memberships.create!(user: @user, role: :owner)
    @project.update!(shipped_at: Time.current)
    assert_not @project.mission_attachable?

    Flipper.enable_actor(:late_mission_attach, @user)
    assert @project.mission_attachable?
  end

  test "hardware mission rejects a software project" do
    hardware_mission = create_mission
    hardware_mission.update!(hardware: true)

    attachment = @project.mission_attachments.create(mission: hardware_mission)

    assert_not attachment.persisted?
    assert_includes attachment.errors[:base].join, "hardware mission"
  end

  test "hardware mission accepts a hardware project" do
    hardware_mission = create_mission
    hardware_mission.update!(hardware: true)
    @project.update!(hardware_stage: "design")

    attachment = @project.mission_attachments.create(mission: hardware_mission)

    assert attachment.persisted?
  end

  test "cannot attach an unrelated mission to a shipped project" do
    @project.mission_attachments.create!(mission: @mission)
    ship_to_mission!(@project, @user, @mission)
    unrelated = create_mission

    @project.current_mission_attachment.detach!
    attachment = @project.mission_attachments.create(mission: unrelated)

    assert_includes attachment.errors[:base], "Can't attach a mission to a project that has already shipped"
  end
end
