require "test_helper"

# Guards the unattended fraud verdict: a cheap order from a buyer whose earlier
# ships all carry a non-fraud integrity verdict skips the review queue. Every
# other case has to stay in front of a person.
class ShopOrderAutoApprovalTest < ActiveSupport::TestCase
  include UserFactory
  include ActiveJob::TestHelper

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    Flipper.enable(:shop_auto_approve)

    @user = create_user(slack_id: "u-auto", display_name: "autobuyer", verified: true)
    @user.update!(has_gotten_free_stickers: true) # clears the shop-tutorial gate

    @item = build_item(usd_cost: 7)
    @address = { "country" => "US", "phone_number" => "+15555550123", "primary" => true }
  end

  teardown { Flipper.disable(:shop_auto_approve) }

  test "a cheap order clears review when every earlier ship passed integrity" do
    ship_with_integrity(:auto_passed)

    order = place_order

    assert_equal "awaiting_periodical_fulfillment", order.reload.aasm_state
  end

  test "a deducted verdict still clears" do
    ship_with_integrity(:deducted, deduction_minutes: 90)

    assert place_order.reload.awaiting_periodical_fulfillment?
  end

  test "a fraud verdict on any earlier ship holds the order" do
    ship_with_integrity(:auto_passed)
    ship_with_integrity(:banned)

    assert place_order.reload.pending?
  end

  test "an undecided check holds the order" do
    ship_with_integrity(:pending)

    assert place_order.reload.pending?
  end

  test "a ship with no integrity check at all holds the order" do
    ship_at(2.days.ago) # no check written for it

    assert place_order.reload.pending?
  end

  test "a buyer with no earlier ships is never cleared vacuously" do
    assert place_order.reload.pending?
  end

  test "ships posted after the order are not considered" do
    ship_with_integrity(:auto_passed, at: 2.days.ago)
    order = place_order
    ship_with_integrity(:banned, at: 1.hour.from_now)

    assert order.reload.awaiting_periodical_fulfillment?,
           "the verdict is taken on the history that existed when the order landed"
  end

  test "the dollar ceiling is exclusive and counts quantity" do
    ship_with_integrity(:auto_passed)
    @item.update!(usd_cost: Shop::AutoApprovable::MAX_AUTO_APPROVE_USD)

    assert place_order.reload.pending?, "an order at the ceiling goes to a person"

    @item.update!(usd_cost: 50)
    assert place_order(quantity: 2).reload.pending?, "2 x $50 reaches the ceiling"
  end

  test "an item with no recorded dollar cost is never cleared" do
    ship_with_integrity(:auto_passed)
    @item.update!(usd_cost: nil)

    assert place_order.reload.pending?
  end

  test "accessory value counts against the parent's ceiling" do
    ship_with_integrity(:auto_passed)
    accessory_item = build_item(usd_cost: 120)

    # One transaction, as Shop::OrdersController places them, so the verdict
    # sees the accessory that the parent ships with.
    order = nil
    perform_enqueued_jobs do
      ActiveRecord::Base.transaction do
        order = @user.shop_orders.create!(shop_item: @item, quantity: 1, frozen_address: @address)
        order.accessory_orders.create!(
          user: @user, shop_item: accessory_item, quantity: 1, frozen_address: @address
        )
      end
    end

    assert order.reload.pending?, "$7 item plus a $120 accessory is over the ceiling"
  end

  test "a self-fulfilling item is fulfilled outright" do
    ship_with_integrity(:auto_passed)
    @item = build_item(usd_cost: 40, type: "ShopItem::SillyItemType")

    assert place_order.reload.fulfilled?
  end

  test "a self-fulfilling item over the ceiling is left for a person" do
    ship_with_integrity(:auto_passed)
    @item = build_item(usd_cost: 100, type: "ShopItem::SillyItemType")

    assert place_order.reload.pending?
  end

  test "a failed fulfilment surfaces for retry and approves nothing" do
    ship_with_integrity(:auto_passed)
    @item = build_item(usd_cost: 40, type: "ShopItem::SillyItemType")

    order = @user.shop_orders.create!(shop_item: @item, quantity: 1, frozen_address: @address)

    assert_raises(Shop::AutoApprovable::FulfilmentFailed) do
      order.shop_item.stub(:fulfill!, ->(*) { raise StandardError, "invalid_grant" }) { order.auto_approve! }
    end

    assert order.reload.pending?, "the order stays in front of a person"
    assert_nil PaperTrail::Version.find_by(item_type: "ShopOrder", item_id: order.id, event: "auto_approved"),
               "a failed attempt must not be recorded as an approval"
  end

  test "a spent retry budget leaves the failure on the order for a reviewer to see" do
    ship_with_integrity(:auto_passed)
    order = place_order

    order.record_auto_approval_failure(StandardError.new("HCB returned 400: invalid_grant"))

    version = PaperTrail::Version.find_by(
      item_type: "ShopOrder", item_id: order.id, event: "auto_approval_failed"
    )

    assert version, "a reviewer opening the order must be able to see the system already tried"
    assert_equal Shop::AutoApprovable::WHODUNNIT, version.whodunnit
    assert_match(/invalid_grant/, version.object_changes["error"])
  end

  test "an order coming off hold goes back to a person" do
    ship_with_integrity(:auto_passed)
    order = place_order

    order.update!(aasm_state: "on_hold")
    perform_enqueued_jobs { order.take_off_hold! }

    assert order.reload.pending?
  end

  test "the flag gates the whole thing" do
    Flipper.disable(:shop_auto_approve)
    ship_with_integrity(:auto_passed)

    assert place_order.reload.pending?
  end

  test "an approval leaves an audit trail carrying its evidence" do
    ship = ship_with_integrity(:auto_passed)
    order = place_order

    version = PaperTrail::Version.find_by(
      item_type: "ShopOrder", item_id: order.id, event: "auto_approved"
    )

    assert version, "an unattended approval must be auditable"
    assert_equal Shop::AutoApprovable::WHODUNNIT, version.whodunnit
    assert_equal [ ship.id ], version.object_changes["cleared_ship_event_ids"]
    assert_equal Shop::AutoApprovable::MAX_AUTO_APPROVE_USD, version.object_changes["usd_ceiling"]
  end

  test "unattended approvals stay out of the reviewer leaderboard" do
    ship_with_integrity(:auto_passed)
    place_order

    assert_empty ShopOrder.leaderboard(:alltime)
  end

  test "a sticky streak sticker clears with no ship history and no flag" do
    Flipper.disable(:shop_auto_approve)

    assert claim_streak_day.reload.awaiting_periodical_fulfillment?
  end

  test "a streak sticker sold outright clears on its type alone" do
    Flipper.disable(:shop_auto_approve)
    @item = build_streak_sticker
    @item.update!(mission_prize_only: false)

    assert place_order.reload.awaiting_periodical_fulfillment?
  end

  test "a streak approval records the item it rested on" do
    order = claim_streak_day

    version = PaperTrail::Version.find_by(
      item_type: "ShopOrder", item_id: order.id, event: "auto_approved"
    )

    assert version, "an unattended approval must be auditable"
    assert_equal "sticky_streak_sticker", version.object_changes["reason"]
    assert_equal order.shop_item_id, version.object_changes["shop_item_id"]
  end

  test "the batch predicate agrees with the per-order one" do
    ship_with_integrity(:auto_passed)
    clean = @user.shop_orders.create!(shop_item: @item, quantity: 1, frozen_address: @address)

    blocked_user = create_user(slack_id: "u-blocked", display_name: "blocked", verified: true)
    blocked_user.update!(has_gotten_free_stickers: true)
    @user, previous = blocked_user, @user
    ship_with_integrity(:pending)
    blocked = blocked_user.shop_orders.create!(shop_item: @item, quantity: 1, frozen_address: @address)
    @user = previous

    ids = ShopOrder.auto_approvable_ids([ clean, blocked ])

    assert_includes ids, clean.id
    assert_not_includes ids, blocked.id
    assert_equal clean.auto_approvable?, ids.include?(clean.id)
    assert_equal blocked.auto_approvable?, ids.include?(blocked.id)
  end

  private

  def build_item(usd_cost:, type: "ShopItem::ThirdPartyPhysical")
    item = ShopItem.new(
      name: "Test Patch #{SecureRandom.hex(4)}",
      description: "A cheap physical item",
      ticket_cost: 0,
      usd_cost: usd_cost,
      type: type,
      enabled: true
    )
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end

  def place_order(quantity: 1)
    order = nil
    perform_enqueued_jobs do
      order = @user.shop_orders.create!(shop_item: @item, quantity: quantity, frozen_address: @address)
    end
    order
  end

  # Mirrors Shop::OrdersController: the order and the claim that unlocked it
  # are saved in one transaction, so the verdict sees the claim.
  def claim_streak_day
    streak = StickyStreak.create!(user: @user, started_on: @user.streak_today_date - 1)
    StreakActivity.create!(user: @user, activity_date: streak.date_for(1),
                           coded_seconds: StreakActivity::DAILY_GOAL_SECONDS)
    sticker = build_streak_sticker
    StickyStreakReward.create!(day_number: 1, shop_item: sticker)

    order = nil
    perform_enqueued_jobs do
      ActiveRecord::Base.transaction do
        order = @user.shop_orders.new(shop_item: sticker, quantity: 1, frozen_address: @address)
        order.redeeming_sticky_streak = streak
        order.save!
        streak.record_claim!(shop_order: order, day: 1)
      end
    end
    order
  end

  def build_streak_sticker
    build_item(usd_cost: 1, type: "ShopItem::StickyStreakSticker")
  end

  def ship_at(time)
    project = Project.create!(title: "Ship #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: @user, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    post = Post.create!(project: project, user: @user, postable: ship_event)
    post.update_column(:created_at, time)
    ship_event
  end

  def ship_with_integrity(status, at: 2.days.ago, deduction_minutes: nil)
    ship_event = ship_at(at)
    attributes = { ship_event: ship_event, status: status, deduction_minutes: deduction_minutes }
    # Decided verdicts carry a reviewer; auto_passed and pending do not.
    attributes[:reviewer] = @user if Certification::Integrity::DECIDED_STATUSES.include?(status.to_s)
    Certification::Integrity.create!(**attributes.compact)
    ship_event
  end
end
