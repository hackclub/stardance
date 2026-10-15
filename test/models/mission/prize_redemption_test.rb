require "test_helper"

# == Schema Information
#
# Table name: mission_prize_redemptions
#
#  id               :bigint           not null, primary key
#  source_type      :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  mission_id       :bigint           not null
#  mission_prize_id :bigint           not null
#  shop_order_id    :bigint           not null
#  source_id        :bigint           not null
#  user_id          :bigint           not null
#
# Indexes
#
#  index_mission_prize_redemptions_on_mission_id        (mission_id)
#  index_mission_prize_redemptions_on_mission_prize_id  (mission_prize_id)
#  index_mission_prize_redemptions_on_shop_order_id     (shop_order_id) UNIQUE
#  index_mission_prize_redemptions_on_source            (source_type,source_id)
#  index_mission_prize_redemptions_on_user_id           (user_id)
#  index_prize_redemptions_on_source_and_prize          (source_type,source_id,mission_prize_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (mission_id => missions.id)
#  fk_rails_...  (mission_prize_id => mission_prizes.id)
#  fk_rails_...  (shop_order_id => shop_orders.id)
#  fk_rails_...  (user_id => users.id)
#
class Mission::PrizeRedemptionTest < ActiveSupport::TestCase
  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  setup do
    @owner = User.create!(email: "owner-#{SecureRandom.hex(6)}@example.com",
                          display_name: "Owner#{SecureRandom.hex(3)}", slack_id: "U#{SecureRandom.hex(8)}",
                          verification_status: :verified, ysws_eligible: true)
    @owner.update!(has_gotten_free_stickers: true) # clears the shop-tutorial gate

    @project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "design")
    Project::Membership.create!(project: @project, user: @owner, role: :owner)
    @mission = create_mission
    @mission.update!(hardware: true)
    @project.mission_attachments.create!(mission: @mission)

    devlog = Post::Devlog.new(body: "initial log", duration_seconds: 3600, phase: "design")
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: @project, user: @owner, postable: devlog)
  end

  test "record! creates a redemption for an after-design funding kit" do
    kit = prize_item("Kit")
    design_prize = @mission.prizes.create!(shop_item: kit, position: 0, category: :after_design)
    funding_request = @project.certification_funding_requests.create!(user: @owner, status: :pending)
    funding_request.update!(status: :approved)

    order = free_order(kit, funding_request)
    redemption = Mission::PrizeRedemption.record!(shop_order: order, gate: funding_request)

    assert redemption.persisted?
    assert_equal funding_request, redemption.source
    assert_equal design_prize, redemption.mission_prize
    assert_equal @owner, redemption.user
    assert_equal @mission, redemption.mission
  end

  test "record! creates a redemption for an after-ship submission and syncs the inline link" do
    reward = prize_item("Reward")
    ship_prize = @mission.prizes.create!(shop_item: reward, position: 0, category: :after_shipping)
    submission = ship_to_mission!(@project, @owner, @mission, status: "approved")

    order = free_order(reward, submission)
    redemption = Mission::PrizeRedemption.record!(shop_order: order, gate: submission)

    assert_equal ship_prize, redemption.mission_prize
    assert_equal submission, redemption.source
    assert_equal order.id, submission.reload.shop_order_id
    assert_equal ship_prize.id, submission.chosen_prize_id
  end

  test "an approved design claims every after-design kit, once each" do
    kits = [ prize_item("Kit A"), prize_item("Kit B") ]
    kits.each_with_index { |kit, i| @mission.prizes.create!(shop_item: kit, position: i, category: :after_design) }
    other = prize_item("After ship")
    @mission.prizes.create!(shop_item: other, position: 0, category: :after_shipping)

    funding_request = @project.certification_funding_requests.create!(user: @owner, status: :pending)
    funding_request.update!(status: :approved)

    assert_equal 2, funding_request.unredeemed_prizes.count
    assert_nil funding_request.redeemable_prize_for(other), "an after-ship prize is not claimable at design"

    kits.each do |kit|
      Mission::PrizeRedemption.record!(shop_order: free_order(kit, funding_request), gate: funding_request)
    end

    assert_equal 2, funding_request.prize_redemptions.count
    assert_empty funding_request.unredeemed_prizes
    assert_not funding_request.prizes_to_claim?
    # A second go at a kit already claimed is no longer redeemable.
    assert_nil funding_request.redeemable_prize_for(kits.first)
  end

  test "an approved submission claims every after-ship prize, once each" do
    rewards = [ prize_item("Reward A"), prize_item("Reward B") ]
    rewards.each_with_index { |item, i| @mission.prizes.create!(shop_item: item, position: i, category: :after_shipping) }
    submission = ship_to_mission!(@project, @owner, @mission, status: "approved")

    first_order = free_order(rewards.first, submission)
    Mission::PrizeRedemption.record!(shop_order: first_order, gate: submission)

    assert submission.prizes_to_claim?, "the second prize is still claimable"

    Mission::PrizeRedemption.record!(shop_order: free_order(rewards.second, submission), gate: submission)

    assert_equal 2, submission.prize_redemptions.count
    assert_not submission.prizes_to_claim?
    # The legacy inline link keeps pointing at the first claim.
    assert_equal first_order.id, submission.reload.shop_order_id
  end

  test "a project cannot claim the same design kit through a later funding request" do
    kit = prize_item("Kit")
    @mission.prizes.create!(shop_item: kit, position: 0, category: :after_design)

    first_request = @project.certification_funding_requests.create!(user: @owner, status: :pending)
    first_request.update!(status: :approved)
    Mission::PrizeRedemption.record!(shop_order: free_order(kit, first_request), gate: first_request)

    @project.update_column(:hardware_stage, "design")
    second_request = @project.certification_funding_requests.create!(user: @owner, status: :pending)
    second_request.update!(status: :approved)

    assert_nil second_request.redeemable_prize_for(kit)
    assert_empty second_request.unredeemed_prizes
  end

  test "record! ignores an item that is not a prize on the gate's mission" do
    kit = prize_item("Kit")
    @mission.prizes.create!(shop_item: kit, position: 0, category: :after_design)
    funding_request = @project.certification_funding_requests.create!(user: @owner, status: :pending)
    funding_request.update!(status: :approved)

    stranger = prize_item("Stranger")
    order = free_order(stranger, funding_request)
    assert_nil Mission::PrizeRedemption.record!(shop_order: order, gate: funding_request)
  end

  private

  def prize_item(name)
    item = ShopItem.new(name: "#{name} #{SecureRandom.hex(3)}", description: "prize item", ticket_cost: 0,
                        type: "ShopItem::ThirdPartyPhysical", enabled: true, mission_prize_only: true)
    item.image.attach(io: StringIO.new(PIXEL_PNG), filename: "i.png", content_type: "image/png")
    item.save!
    item
  end

  def free_order(item, gate)
    order = @owner.shop_orders.new(shop_item: item, quantity: 1,
                                   frozen_address: { "country" => "US", "phone_number" => "+15555550123" })
    order.redeeming_funding_request = gate if gate.is_a?(Certification::FundingRequest)
    order.redeeming_mission_submission = gate if gate.is_a?(Mission::Submission)
    order.aasm_state = "pending"
    order.save!
    order
  end
end
