require "test_helper"

class HardwareKitRedemptionTest < ActionDispatch::IntegrationTest
  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  setup do
    @owner = User.create!(email: "owner-#{SecureRandom.hex(6)}@example.com",
                          display_name: "Owner#{SecureRandom.hex(3)}", slack_id: "U#{SecureRandom.hex(8)}",
                          verification_status: :verified, ysws_eligible: true)
    @stranger = User.create!(email: "str-#{SecureRandom.hex(6)}@example.com",
                             display_name: "Str#{SecureRandom.hex(3)}", slack_id: "U#{SecureRandom.hex(8)}")
    @project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "design")
    Project::Membership.create!(project: @project, user: @owner, role: :owner)
    @mission = create_mission
    @mission.update!(hardware: true)
    @project.mission_attachments.create!(mission: @mission)

    devlog = Post::Devlog.new(body: "log", duration_seconds: 3600, phase: "design")
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: @project, user: @owner, postable: devlog)

    @kit = ShopItem.new(name: "Hackpad Kit #{SecureRandom.hex(3)}", description: "the kit", ticket_cost: 0,
                        type: "ShopItem::ThirdPartyPhysical", enabled: true, mission_prize_only: true)
    @kit.image.attach(io: StringIO.new(PIXEL_PNG), filename: "kit.png", content_type: "image/png")
    @kit.save!
    @mission.prizes.create!(shop_item: @kit, position: 0, category: :after_design)

    @funding_request = @project.certification_funding_requests.create!(user: @owner, status: :pending)
    @funding_request.update!(status: :approved)
  end

  test "the kit page renders a redeem form for the approved request owner" do
    sign_in @owner
    get shop_item_path(@kit, funding_request_id: @funding_request.id)
    assert_response :success
    assert_select "input[name=?][value=?]", "funding_request_id", @funding_request.id.to_s
  end

  test "the kit is not redeemable by a non-owner" do
    sign_in @stranger
    get shop_item_path(@kit, funding_request_id: @funding_request.id)
    assert_redirected_to shop_path
  end

  test "a second kit on the same mission stays claimable after the first is claimed" do
    second_kit = ShopItem.new(name: "Extra Kit #{SecureRandom.hex(3)}", description: "the other kit", ticket_cost: 0,
                              type: "ShopItem::ThirdPartyPhysical", enabled: true, mission_prize_only: true)
    second_kit.image.attach(io: StringIO.new(PIXEL_PNG), filename: "kit2.png", content_type: "image/png")
    second_kit.save!
    @mission.prizes.create!(shop_item: second_kit, position: 1, category: :after_design)

    @owner.update!(has_gotten_free_stickers: true) # clears the shop-tutorial gate
    order = @owner.shop_orders.new(shop_item: @kit, quantity: 1,
                                   frozen_address: { "country" => "US", "phone_number" => "+15555550123" })
    order.redeeming_funding_request = @funding_request
    order.aasm_state = "pending"
    order.save!
    Mission::PrizeRedemption.record!(shop_order: order, gate: @funding_request)

    sign_in @owner
    get shop_item_path(second_kit, funding_request_id: @funding_request.id)
    assert_response :success

    get shop_item_path(@kit, funding_request_id: @funding_request.id)
    assert_redirected_to shop_path, "an already-claimed kit stops being redeemable"
  end

  test "the kit is not redeemable without an approved request" do
    @funding_request.update!(status: :returned, feedback: "nope")
    sign_in @owner
    get shop_item_path(@kit, funding_request_id: @funding_request.id)
    assert_redirected_to shop_path
  end
end
