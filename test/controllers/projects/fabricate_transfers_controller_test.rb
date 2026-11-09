require "test_helper"

class Projects::FabricateTransfersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user(slack_id: "U_FAB_OWNER", display_name: "fab-owner", verified: true)
    @project = Project.create!(title: "Split keyboard")
    @project.memberships.create!(user: @owner, role: :owner)
    @project.update!(hardware_stage: "design")

    sign_in @owner
  end

  test "the owner moves a design-stage project and is sent to Fabricate to import it" do
    assert_difference -> { Project::FabricateTransfer.count }, 1 do
      post project_fabricate_transfer_path(@project)
    end

    assert_equal @owner, @project.reload.fabricate_transfer.user
    assert_redirected_to "#{Project::FabricateTransfer::BASE_URL}/imports/stardance/#{@project.id}"
  end

  test "a project waiting on a funding review stays put" do
    add_devlog
    @project.certification_funding_requests.create!(user: @owner, complexity_tier: 2, requested_amount_cents: 4_000, status: :pending)

    assert_not_transferred
  end

  test "a build-stage project stays put" do
    @project.update!(hardware_stage: "build")

    assert_not_transferred
  end

  test "a teammate who doesn't own the project can't move it" do
    teammate = create_user(slack_id: "U_FAB_MATE", display_name: "fab-mate")
    @project.memberships.create!(user: teammate, role: :contributor)
    sign_in teammate

    assert_not_transferred
  end

  test "an owner who never linked Hack Club can't move it" do
    @owner.hack_club_identity.destroy!

    assert_not_transferred
  end

  test "an owner who hasn't verified their ID can't move it, since Fabricate couldn't see their devlogs" do
    @owner.update!(verification_status: :needs_submission)

    assert_not_transferred
  end

  test "the project page offers the move to its owner and links a moved project" do
    get project_path(@project)
    assert_select "button.action-btn--fabricate", text: "Move to Fabricate"
    assert_select "dialog#fabricate-transfer-#{@project.id} form[action=?]", project_fabricate_transfer_path(@project)

    @project.create_fabricate_transfer!(user: @owner)
    get project_path(@project)
    assert_select "a.action-btn--fabricate[href=?]", "#{Project::FabricateTransfer::BASE_URL}/imports/stardance/#{@project.id}"
    assert_select "dialog#fabricate-transfer-#{@project.id}", count: 0
  end

  private

  def assert_not_transferred
    assert_no_difference -> { Project::FabricateTransfer.count } do
      post project_fabricate_transfer_path(@project)
    end
  end

  def add_devlog
    devlog = Post::Devlog.new(body: "Routed the PCB", duration_seconds: 3600, phase: "design")
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: @project, user: @owner, postable: devlog)
  end
end
