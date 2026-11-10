require "test_helper"

# hardware_stage decides how a ship is paid (flat rate, no review window), so it
# must not be editable once a project has committed to a payout path: after a
# funding request or after shipping.
class ProjectHardwareStageLockTest < ActiveSupport::TestCase
  setup do
    @user = create_user(slack_id: "U_PHSL", display_name: "phsl")
    @project = Project.create!(title: "Rover")
    @project.memberships.create!(user: @user, role: :owner)
  end

  test "hardware stage cannot be changed after the project has shipped" do
    @project.update!(hardware_stage: "design")
    ship = Post::ShipEvent.new(body: "shipped", uploading_attachments: true)
    ActiveRecord::Base.transaction do
      ship.save!(validate: false)
      Post.create!(project: @project, user: @user, postable: ship)
    end

    @project.reload
    assert_not @project.update(hardware_stage: "build")
    assert_includes @project.errors[:hardware_stage].join, "after the project has shipped"
  end

  test "a software project cannot be flipped to hardware after shipping" do
    ship = Post::ShipEvent.new(body: "shipped", uploading_attachments: true)
    ActiveRecord::Base.transaction do
      ship.save!(validate: false)
      Post.create!(project: @project, user: @user, postable: ship)
    end

    @project.reload
    assert_not @project.update(hardware_stage: "build")
  end

  test "an unshipped project can still change stage freely" do
    assert @project.update(hardware_stage: "design")
    assert @project.update(hardware_stage: "build")
  end

  test "the funding approval path can still advance the stage" do
    @project.update!(hardware_stage: "design")
    @project.advancing_via_funding_approval = true

    assert @project.update(hardware_stage: "build")
  end
end
