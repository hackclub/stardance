require "test_helper"
require "base64"
require "stringio"

class Shop::OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(
      slack_id: "U_MISSION_PRIZE_#{SecureRandom.hex(6)}",
      display_name: "mission-prize-#{SecureRandom.hex(4)}"
    )
    @user.update!(verification_status: "verified", ysws_eligible: true, has_gotten_free_stickers: true)

    @shop_item = ShopItem.new(
      name: "Mission Prize #{SecureRandom.hex(4)}",
      description: "Mission-only prize",
      ticket_cost: 0,
      type: "ShopItem::ThirdPartyPhysical",
      enabled: true,
      enabled_us: true,
      mission_prize_only: true
    )
    @shop_item.image.attach(
      io: StringIO.new(Base64.decode64(test_png)),
      filename: "mission_prize.png",
      content_type: "image/png"
    )
    @shop_item.save!
    @mission = Mission.create!(
      slug: "mission-prize-#{SecureRandom.hex(6)}",
      name: "Mission Prize",
      description: "Complete the mission"
    )
    @prize = @mission.prizes.create!(shop_item: @shop_item)
    @submission = create_approved_submission(@user, @mission)

    sign_in @user
  end

  test "mission redemption form keeps submission id" do
    with_identity_payload do
      get shop_item_path(@shop_item, mission_submission_id: @submission.id)
    end

    assert_response :success
    assert_select "input[type=hidden][name=mission_submission_id][value=?]", @submission.id.to_s
  end

  test "approved mission submission redeems mission-only prize" do
    with_identity_payload do
      assert_difference("ShopOrder.count", 1) do
        post shop_orders_path(shop_item_id: @shop_item.id), params: order_params(@submission)
      end
    end

    assert_redirected_to shop_orders_path
    @submission.reload
    assert_not_nil @submission.shop_order_id
    assert_equal @prize.id, @submission.chosen_prize_id

    order = ShopOrder.find(@submission.shop_order_id)
    assert_equal @user.id, order.user_id
    assert_equal @shop_item.id, order.shop_item_id
    assert_equal 1, order.quantity
  end

  test "already redeemed mission submission cannot create another order" do
    with_identity_payload do
      post shop_orders_path(shop_item_id: @shop_item.id), params: order_params(@submission)
    end

    order_id = @submission.reload.shop_order_id

    with_identity_payload do
      assert_no_difference("ShopOrder.count") do
        post shop_orders_path(shop_item_id: @shop_item.id), params: order_params(@submission)
      end
    end

    assert_redirected_to shop_path
    assert_equal order_id, @submission.reload.shop_order_id
  end

  private

  def create_approved_submission(user, mission)
    project = Project.create!(
      title: "Mission Project #{SecureRandom.hex(4)}",
      description: "Built for a mission"
    )
    project.memberships.create!(user: user, role: :owner)

    ship_event = Post::ShipEvent.new(
      body: "Finished the mission",
      certification_status: "approved"
    )
    ship_event.attachments.attach(
      io: StringIO.new(Base64.decode64(test_png)),
      filename: "ship.png",
      content_type: "image/png"
    )
    ship_event.save!
    project.posts.create!(user: user, postable: ship_event)

    submission = Mission::Submission.create!(
      mission: mission,
      ship_event: ship_event,
      payout_path: "static_prize"
    )
    submission.certify!
    submission.approve!
    submission
  end

  def order_params(submission)
    {
      mission_submission_id: submission.id,
      quantity: 3,
      address_id: address_payload.fetch("id")
    }
  end

  def with_identity_payload(&block)
    original = HCAService.method(:identity)
    payload = hca_payload
    HCAService.define_singleton_method(:identity) { |*_args| payload }
    block.call
  ensure
    HCAService.define_singleton_method(:identity, original)
  end

  def hca_payload
    {
      "addresses" => [ address_payload ],
      "phone_number" => "+15555555555"
    }
  end

  def address_payload
    {
      "id" => "addr_1",
      "primary" => true,
      "country" => "US",
      "line1" => "1 Test St",
      "city" => "New York",
      "state" => "NY",
      "postal_code" => "10001"
    }
  end

  def test_png
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
  end
end
