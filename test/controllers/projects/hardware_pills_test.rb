# frozen_string_literal: true

require "test_helper"

class Projects::HardwarePillsTest < ActionDispatch::IntegrationTest
  HCB_GRANT_RESPONSE = { "id" => "test_grant_pills" }.freeze

  setup do
    Flipper.enable(:hardware_flow)

    @owner = create_user(slack_id: "U_PILLS_OWNER", display_name: "pillsowner")
    @reviewer = create_user(slack_id: "U_PILLS_REVIEWER", display_name: "pillsreviewer")
    @outsider = create_user(slack_id: "U_PILLS_OUTSIDER", display_name: "pillsoutsider")
  end

  teardown do
    Flipper.disable(:hardware_flow)
  end

  test "a software project shows no pills" do
    project = create_project(hardware_stage: nil)
    sign_in @owner

    get project_path(project)

    assert_response :success
    assert_select ".project-show__tag", 0
  end

  test "a hardware project without funding shows only the type and stage pills" do
    project = create_project(hardware_stage: "design")
    sign_in @owner

    get project_path(project)

    assert_response :success
    assert_select ".project-show__tag--hardware", text: "Hardware"
    assert_select ".project-show__tag--stage", text: "Design Stage"
    assert_select ".project-show__tag--tier", 0
    assert_select ".project-show__tag--approved-design", 0
    assert_select ".project-show__tag--approved-build", 0
  end

  test "an approved funding request adds the tier and design approval pills" do
    project = approve_funding_for(create_project(hardware_stage: "design"))
    sign_in @owner

    get project_path(project)

    assert_response :success
    assert_select ".project-show__tag--tier-s", text: "S Tier"
    assert_select ".project-show__tag--stage", text: "Build Stage"
    assert_select ".project-show__tag--approved-design", text: "Design Approved"
  end

  test "a pending build review shows no build approval pill" do
    project = create_project(hardware_stage: "build", ship_status: "submitted")
    project.ship_reviews.create!(status: :pending)
    sign_in @owner

    get project_path(project)

    assert_response :success
    assert_select ".project-show__tag--approved-build", 0
  end

  test "an approved build review adds the build approval pill" do
    project = create_project(hardware_stage: "build", ship_status: "submitted")
    project.ship_reviews.create!(status: :approved, reviewer: @reviewer)
    sign_in @owner

    get project_path(project)

    assert_response :success
    assert_select ".project-show__tag--approved-build", text: "Build Approved"
    # Only the build is approved, so the stage pill still has something to say.
    assert_select ".project-show__tag--stage", text: "Build Stage"
  end

  test "the stage pill drops out once both reviews are approved" do
    project = approve_funding_for(create_project(hardware_stage: "design"))
    project.update!(ship_status: "submitted")
    project.ship_reviews.create!(status: :approved, reviewer: @reviewer)
    sign_in @owner

    get project_path(project)

    assert_response :success
    assert_select ".project-show__tag--approved-design", text: "Design Approved"
    assert_select ".project-show__tag--approved-build", text: "Build Approved"
    assert_select ".project-show__tag--stage", 0
  end

  test "the pills are public — an outsider sees them too" do
    project = approve_funding_for(create_project(hardware_stage: "design"))
    sign_in @outsider

    get project_path(project)

    assert_response :success
    assert_select ".project-show__tag--hardware", text: "Hardware"
    assert_select ".project-show__tag--tier-s", text: "S Tier"
    assert_select ".project-show__tag--approved-design", text: "Design Approved"
  end

  private

  def create_project(**attrs)
    project = Project.create!(title: "Pill Rig #{SecureRandom.hex(4)}", description: "A rig", **attrs)
    project.memberships.create!(user: @owner, role: :owner)
    project
  end

  # A funding request needs a devlog to exist before it can be submitted, and
  # approving one issues an HCB card grant we don't want to call for real.
  def approve_funding_for(project)
    devlog = Post::Devlog.new(body: "design log", duration_seconds: 3600, phase: "design")
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: @owner, postable: devlog)

    request = project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 3, requested_amount_cents: 6_000
    )
    HCBService.stub(:create_card_grant, HCB_GRANT_RESPONSE) do
      request.update!(reviewer: @reviewer, status: :approved)
    end

    project.reload
  end
end
