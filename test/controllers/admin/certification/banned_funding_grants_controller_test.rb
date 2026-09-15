require "test_helper"

# The admin claw-back report: approved funding requests whose recipient is now
# banned, and the control that cancels the issued HCB card grant. HCB is stubbed
# throughout — cancelling here hits a real card grant in production.
class Admin::Certification::BannedFundingGrantsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:hardware_flow)
    @admin = create_user(slack_id: "U_BFG_ADMIN", display_name: "bfg-admin")
    @admin.grant_role!(:admin)
    @reviewer = create_user(slack_id: "U_BFG_REV", display_name: "bfg-rev")
    @reviewer.grant_role!(:admin)
    @owner = create_user(slack_id: "U_BFG_OWNER", display_name: "bfg-owner", verified: true)

    @project = Project.create!(title: "BFG #{SecureRandom.hex(3)}", hardware_stage: "design")
    @project.memberships.create!(user: @owner, role: :owner)
    add_devlog(@project, "design")
    @funding = approved_funding_with_grant
  end

  teardown { Flipper.disable(:hardware_flow) }

  test "index lists approved grants to banned users and hides good-standing ones" do
    sign_in @admin

    get admin_certification_banned_funding_grants_path
    assert_response :success
    assert_not_includes @response.body, @project.title,
      "a grant to a user in good standing must not be listed"

    @owner.update!(banned: true)
    get admin_certification_banned_funding_grants_path
    assert_response :success
    assert_includes @response.body, @project.title
  end

  test "cancel_grant cancels the HCB grant, reverses the request, and audits it" do
    @owner.update!(banned: true)
    sign_in @admin

    cancel_args = nil
    HCBService.stub(:cancel_card_grant!, ->(hashid:) { cancel_args = hashid; { "status" => "canceled" } }) do
      assert_difference -> { PaperTrail::Version.where(event: "hcb_grant_canceled").count }, 1 do
        delete cancel_grant_admin_certification_banned_funding_grant_path(@funding)
      end
    end

    assert_equal "cdg_test", cancel_args, "the issued grant's hashid is cancelled in HCB"
    assert_redirected_to admin_certification_banned_funding_grants_path
    assert @funding.reload.reversed_at.present?, "the request is marked reversed"
    assert @funding.approved?, "cancelling the grant doesn't rewind the verdict"

    # The reversed row drops off the report.
    assert_empty ::Certification::FundingRequest.with_banned_owner_grant
    get admin_certification_banned_funding_grants_path
    assert_includes @response.body, "banned-grants__empty"
  end

  test "cancel_grant is refused for a non-admin reviewer" do
    @owner.update!(banned: true)
    @reviewer.remove_role!(:admin)
    @reviewer.grant_role!(:project_certifier)
    sign_in @reviewer

    assert_no_difference -> { PaperTrail::Version.where(event: "hcb_grant_canceled").count } do
      delete cancel_grant_admin_certification_banned_funding_grant_path(@funding)
    end

    assert_response :forbidden
    assert @funding.reload.reversed_at.blank?, "a refused cancel leaves the grant intact"
  end

  private

  def add_devlog(project, phase)
    devlog = Post::Devlog.new(body: "log", duration_seconds: 3600, phase: phase)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: @owner, postable: devlog)
  end

  def approved_funding_with_grant
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 3, requested_amount_cents: 6_000, status: :pending
    )
    HCBService.stub(:create_card_grant, { "id" => "cdg_test" }) do
      fr.update!(reviewer: @reviewer, status: :approved, feedback: "great")
    end
    fr.reload
  end
end
