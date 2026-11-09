require "test_helper"

class Projects::FabricateTransfersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user(slack_id: "U_FAB_OWNER", display_name: "fab-owner", verified: true)
    @project = Project.create!(title: "Split keyboard")
    @project.memberships.create!(user: @owner, role: :owner)
    @project.update!(hardware_stage: "design")

    sign_in @owner
  end

  test "the owner moves a design-stage project and is sent to it on Fabricate" do
    FabricateService.stub(:import_project!, 77) do
      assert_difference -> { Project::FabricateTransfer.count }, 1 do
        post project_fabricate_transfer_path(@project)
      end
    end

    transfer = @project.reload.fabricate_transfer
    assert_equal [ 77, @owner ], [ transfer.fabricate_project_id, transfer.user ]
    assert_redirected_to "#{FabricateService::BASE_URL}/projects/77?from=stardance"
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

  test "when Fabricate can't be reached nothing is recorded and the owner is told" do
    FabricateService.stub(:import_project!, ->(*, **) { raise FabricateService::Error, "timeout" }) do
      assert_no_difference -> { Project::FabricateTransfer.count } do
        post project_fabricate_transfer_path(@project)
      end
    end

    assert_redirected_to project_path(@project)
    assert_match "couldn't reach Fabricate", flash[:alert]
  end

  test "an owner who never linked Hack Club can't move it, since Fabricate trusts the email" do
    @owner.hack_club_identity.destroy!

    assert_not_transferred
  end

  test "the project page offers the move to its owner and links a moved project" do
    get project_path(@project)
    assert_select "button.action-btn--fabricate", text: "Move to Fabricate"
    assert_select "dialog#fabricate-transfer-#{@project.id} form[action=?]", project_fabricate_transfer_path(@project)

    @project.create_fabricate_transfer!(user: @owner, fabricate_project_id: 77)
    get project_path(@project)
    assert_select "a.action-btn--fabricate[href=?]", "#{FabricateService::BASE_URL}/projects/77?from=stardance"
    assert_select "dialog#fabricate-transfer-#{@project.id}", count: 0
  end

  private

  def assert_not_transferred
    FabricateService.stub(:import_project!, ->(*, **) { flunk "Fabricate shouldn't be called" }) do
      assert_no_difference -> { Project::FabricateTransfer.count } do
        post project_fabricate_transfer_path(@project)
      end
    end
  end

  def add_devlog
    devlog = Post::Devlog.new(body: "Routed the PCB", duration_seconds: 3600, phase: "design")
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: @project, user: @owner, postable: devlog)
  end
end
