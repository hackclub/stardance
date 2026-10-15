require "test_helper"

class HardwareKitFundingSubmissionTest < ActionDispatch::IntegrationTest
  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  setup do
    Flipper.enable(:hardware_flow)
    @owner = User.create!(email: "owner-#{SecureRandom.hex(6)}@example.com",
                          display_name: "Owner#{SecureRandom.hex(3)}", slack_id: "U#{SecureRandom.hex(8)}",
                          verification_status: :verified, ysws_eligible: true)
    @project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "design")
    Project::Membership.create!(project: @project, user: @owner, role: :owner)
    @mission = create_mission
    @mission.update!(hardware: true)
    @project.mission_attachments.create!(mission: @mission)

    devlog = Post::Devlog.new(body: "log", duration_seconds: 3600, phase: "design")
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: @project, user: @owner, postable: devlog)
  end

  test "kit mission: submitting a design with no tier or amount creates a valid request" do
    add_after_design_kit

    sign_in @owner
    assert_difference -> { @project.certification_funding_requests.count }, 1 do
      post project_funding_request_path(@project)
    end
    assert_redirected_to project_path(@project)

    request = @project.certification_funding_requests.last
    assert request.awards_design_kit?
    assert_equal 0, request.requested_amount_cents
    assert_includes Certification::FundingRequest::TIER_MAX_CENTS.keys, request.complexity_tier
  end

  # A builder who already has the parts (or has claimed this mission's kit
  # before) still gets the design approved, just without a kit going out.
  test "kit mission: approving without a kit advances the build and owes nothing" do
    add_after_design_kit
    request = kit_request

    request.update!(reviewer: reviewer, verdict: "approved_without_grant")

    assert request.reload.approved?
    assert request.prizes_waived?
    assert_not request.awards_design_kit?
    assert request.kit_mission?, "the mission still hands out a kit; this approval just waived it"
    assert_empty request.unredeemed_prizes
    assert_not request.prizes_to_claim?
    assert_equal "build", @project.reload.hardware_stage
    assert_nil request.hcb_grant_hashid
  end

  test "kit mission: a waived kit cannot be claimed in the shop" do
    add_after_design_kit
    request = kit_request
    kit = @mission.prizes.first.shop_item

    request.update!(reviewer: reviewer, verdict: "approved_without_grant")

    sign_in @owner
    get shop_item_path(kit, funding_request_id: request.id)

    assert_redirected_to shop_path
    assert_nil request.redeemable_prize_for(kit),
               "the shop's free-price gate asks the request what it still owes"
  end

  test "kit mission: an approved kit is still claimable in the shop" do
    add_after_design_kit
    request = kit_request
    kit = @mission.prizes.first.shop_item

    request.update!(reviewer: reviewer, verdict: "approved")

    sign_in @owner
    get shop_item_path(kit, funding_request_id: request.id)

    assert_response :success
    assert_equal @mission.prizes.first, request.redeemable_prize_for(kit)
  end

  test "kit mission: approving normally still sends the kit" do
    add_after_design_kit
    request = kit_request

    request.update!(reviewer: reviewer, verdict: "approved")

    assert request.reload.awards_design_kit?
    assert_not request.prizes_waived?
    assert request.prizes_to_claim?
    assert_equal "build", @project.reload.hardware_stage
  end

  test "non-kit mission: submitting without a tier or amount is rejected" do
    sign_in @owner
    assert_no_difference -> { @project.certification_funding_requests.count } do
      post project_funding_request_path(@project)
    end
  end

  private

  def kit_request
    @project.certification_funding_requests.create!(user: @owner, status: :pending)
  end

  def reviewer
    @reviewer ||= User.create!(email: "rev-#{SecureRandom.hex(6)}@example.com",
                               display_name: "Rev#{SecureRandom.hex(3)}", slack_id: "U#{SecureRandom.hex(8)}")
  end

  def add_after_design_kit
    kit = ShopItem.new(name: "Kit #{SecureRandom.hex(3)}", description: "the kit", ticket_cost: 0,
                       type: "ShopItem::ThirdPartyPhysical", enabled: true, mission_prize_only: true)
    kit.image.attach(io: StringIO.new(PIXEL_PNG), filename: "kit.png", content_type: "image/png")
    kit.save!
    @mission.prizes.create!(shop_item: kit, position: 0, category: :after_design)
  end
end
