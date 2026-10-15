require "test_helper"

class Admin::Missions::HardwareReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:hardware_flow)
    @owner = create_user(slack_id: "U_MHW_OWNER", display_name: "mhw-owner", verified: true)
    @reviewer = create_user(slack_id: "U_MHW_REV", display_name: "mhw-reviewer")
    @outsider = create_user(slack_id: "U_MHW_OUT", display_name: "mhw-outsider")

    @mission = create_mission
    @mission.update!(hardware: true)
    @mission.memberships.create!(user: @reviewer, role: :reviewer)

    @design_project = attach_hardware_project("Kit design bot", "design")
    add_devlog(@design_project)
    @funding = @design_project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 4_200, status: :pending
    )

    @build_project = attach_hardware_project("Kit build bot", "build")
    @ship = ::Certification::Ship.create!(project: @build_project, status: :pending)
  end

  teardown { Flipper.disable(:hardware_flow) }

  test "a per-mission reviewer sees the mission's design and build queues" do
    sign_in @reviewer

    get design_admin_mission_hardware_reviews_path(@mission.slug)
    assert_response :success
    assert_select ".ship-queue__project-title", text: /Kit design bot/

    get build_admin_mission_hardware_reviews_path(@mission.slug)
    assert_response :success
    assert_select ".ship-queue__project-title", text: /Kit build bot/
  end

  test "a non-reviewer cannot access the mission hardware dash" do
    sign_in @outsider
    get design_admin_mission_hardware_reviews_path(@mission.slug)
    assert_response :forbidden
  end

  test "the overview links a hardware mission to its hardware dash with pending funding and ship counts" do
    sign_in @reviewer
    get admin_mission_reviews_path
    assert_response :success
    assert_select "a[href=?]", design_admin_mission_hardware_reviews_path(@mission.slug)
    assert_select ".mission-overview__card-pending", text: /2 pending/
  end

  HCB_GRANT_RESPONSE = { "id" => "test_grant_mhw" }.freeze

  test "a per-mission reviewer can claim a funding request and is returned to the mission dash" do
    sign_in @reviewer
    post admin_certification_funding_request_claim_path(@funding)
    assert_redirected_to admin_mission_hardware_review_path(@mission.slug, @design_project)
    assert_equal @reviewer.id, @funding.reload.reviewer_id
  end

  test "a per-mission reviewer can approve a funding request and is returned to the mission dash queue" do
    ::Certification::FundingRequest.atomic_claim!(@funding.id, @reviewer)
    sign_in @reviewer

    HCBService.stub(:create_card_grant, HCB_GRANT_RESPONSE) do
      patch admin_certification_funding_request_path(@funding),
            params: { redirect_to_hardware: @design_project.id,
                      certification_funding_request: { verdict: "approved", feedback: "looks good" } }
    end

    assert_redirected_to next_admin_mission_hardware_reviews_path(@mission.slug, stage: "design")
    assert @funding.reload.approved?
  end

  test "the mission hardware dash renders the per-project review page" do
    sign_in @reviewer
    get admin_mission_hardware_review_path(@mission.slug, @design_project)
    assert_response :success
  end

  test "the software submission dash for a hardware mission redirects to the hardware dash" do
    sign_in @reviewer
    get admin_mission_submissions_path(@mission.slug)
    assert_redirected_to design_admin_mission_hardware_reviews_path(@mission.slug)
  end

  test "hardware mission submissions are excluded from the all-missions software queue" do
    ship_to_mission!(@build_project, @owner, @mission, status: "pending")
    admin = create_user(slack_id: "U_MHW_ADMIN2", display_name: "mhw-admin2")
    admin.grant_role!(:admin)
    sign_in admin

    get admin_mission_submissions_path("all")
    assert_response :success
    assert_select ".mission-queue__project-title", text: /Kit build bot/, count: 0
  end

  test "mission-attached hardware is excluded from the global hardware dash" do
    admin = create_user(slack_id: "U_MHW_ADMIN", display_name: "mhw-admin")
    admin.grant_role!(:admin)
    sign_in admin

    get design_admin_certification_hardware_reviews_path
    assert_response :success
    assert_select ".ship-queue__project-title", text: /Kit design bot/, count: 0
  end

  private

  def attach_hardware_project(title, stage)
    project = Project.create!(title: title)
    project.memberships.create!(user: @owner, role: :owner)
    project.update!(hardware_stage: stage)
    project.mission_attachments.create!(mission: @mission)
    project
  end

  def add_devlog(project)
    devlog = Post::Devlog.new(body: "log", duration_seconds: 3600, phase: project.hardware_stage)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: @owner, postable: devlog)
  end
end
