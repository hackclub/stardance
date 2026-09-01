require "test_helper"

# The fraud queue is worked oldest-first, with the orders the automation would
# clear on its own pushed to the bottom so reviewers spend their attention on
# the ones needing a judgement.
class Admin::Shop::OrdersControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    Flipper.enable(:shop_auto_approve)

    @admin = create_user(slack_id: "U_SO_ADMIN", display_name: "so_admin")
    @admin.grant_role!(:admin)

    @item = ShopItem.new(
      name: "Queue Patch", description: "A cheap physical item",
      ticket_cost: 0, usd_cost: 7, type: "ShopItem::ThirdPartyPhysical", enabled: true
    )
    @item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    @item.save!

    @address = { "country" => "US", "primary" => true }
  end

  teardown { Flipper.disable(:shop_auto_approve) }

  test "the queue is oldest first, with auto-approvable orders last" do
    # Newest of the three, and needs a human, so it must still outrank the
    # auto-approvable one placed before it.
    needs_review = order_for(buyer("needs-review", integrity: :pending), at: 1.hour.ago)
    older_needs_review = order_for(buyer("older", integrity: :banned), at: 3.hours.ago)
    auto = order_for(buyer("auto", integrity: :auto_passed), at: 2.hours.ago)

    sign_in @admin
    get admin_shop_orders_path(view: "shop_orders", status: "pending")

    assert_response :success
    assert_equal [ older_needs_review.id, needs_review.id, auto.id ], rendered_order_ids
  end

  test "an auto-approvable row is marked so a reviewer can see why it sank" do
    order_for(buyer("auto", integrity: :auto_passed), at: 1.hour.ago)

    sign_in @admin
    get admin_shop_orders_path(view: "shop_orders", status: "pending")

    assert_select "tr.shop-orders__row--auto-approvable", 1
    assert_select ".shop-orders__auto-approve-tag"
  end

  test "the fraud queue is labelled as one" do
    sign_in @admin
    get admin_shop_orders_path(view: "shop_orders")

    assert_response :success
    assert_select "h1", text: /Fraud Review/
  end

  test "streak stickers are left out of the fulfillment stats but stay in the queue" do
    packer = buyer("packer", integrity: :auto_passed)
    real_order = order_for(packer, at: 2.hours.ago)
    real_order.update_columns(aasm_state: "awaiting_periodical_fulfillment")

    sticker_order = packer.shop_orders.create!(
      shop_item: streak_sticker, quantity: 1, frozen_address: @address
    )
    sticker_order.update_columns(aasm_state: "awaiting_periodical_fulfillment")

    sign_in @admin
    get admin_shop_orders_path(view: "fulfillment")

    assert_response :success
    assert_select ".badge-awaiting_periodical_fulfillment .shop-orders__stat-count",
                  text: "1", message: "the headline count must ignore the sticker"
    assert_includes rendered_order_ids, sticker_order.id,
                    "the sticker still has to be packed, so it stays in the queue"
    assert_select ".shop-orders__stats-note"
  end

  test "streak stickers get their own toggle instead of inflating the mail pile" do
    packer = buyer("mailer", integrity: :auto_passed)
    packer.shop_orders.create!(shop_item: streak_sticker, quantity: 1, frozen_address: @address)
                      .update_columns(aasm_state: "awaiting_periodical_fulfillment")

    sign_in @admin
    get admin_shop_orders_path(view: "fulfillment", hidden_types: [ "ShopItem::StickyStreakSticker" ])

    assert_select ".shop-orders__type-toggle-count", text: "1",
                  message: "the folded-away stickers report their own count"
    assert_not_includes Admin::Shop::OrdersController::ITEM_TYPE_TOGGLES
                          .find { |toggle| toggle[:label] == "HQ Mail" }[:types],
                        "ShopItem::StickyStreakSticker"
  end

  private

  def streak_sticker
    item = ShopItem.new(
      name: "Streak Sticker", description: "Earned by keeping the streak",
      ticket_cost: 0, usd_cost: 1, type: "ShopItem::StickyStreakSticker", enabled: true,
      mission_prize_only: false
    )
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end

  # Ids in the order the table rendered them.
  def rendered_order_ids
    css_select("tbody tr td:first-child").map { |cell| cell.text[/#(\d+)/, 1].to_i }
  end

  def buyer(name, integrity:)
    user = create_user(slack_id: "U_SO_#{name}", display_name: "so_#{name}", verified: true)
    user.update!(has_gotten_free_stickers: true)

    project = Project.create!(title: "Ship #{name}")
    Project::Membership.create!(project: project, user: user, role: :owner)
    ship = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    post = Post.create!(project: project, user: user, postable: ship)
    post.update_column(:created_at, 5.days.ago)

    check = Certification::Integrity.new(ship_event: ship, status: integrity)
    check.reviewer = user if Certification::Integrity::DECIDED_STATUSES.include?(integrity.to_s)
    check.save!

    user
  end

  def order_for(user, at:)
    order = user.shop_orders.create!(shop_item: @item, quantity: 1, frozen_address: @address)
    # Auto-approval runs off a job, so nothing has cleared it yet; this is the
    # pre-existing backlog the sort is really for.
    order.update_columns(created_at: at, aasm_state: "pending")
    order
  end
end
