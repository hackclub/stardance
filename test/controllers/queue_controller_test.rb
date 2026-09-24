require "test_helper"

class QueueControllerTest < ActionDispatch::IntegrationTest
  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  setup do
    @user = users(:one)
    @listed = build_item("USB Blaster")
    @unlisted = build_item("Secret Prize", unlisted: true)
  end

  test "renders an empty queue without any orders" do
    get queue_path

    assert_response :success
    assert_select ".queue__stat-value", text: "0"
    assert_includes response.body, "the queue is completely clear"
  end

  test "counts pending orders and bands them by age" do
    build_order(@listed, aasm_state: "pending", created_at: 2.hours.ago)
    build_order(@listed, aasm_state: "pending", created_at: 10.days.ago)

    get queue_path

    assert_response :success
    assert_select ".queue__stat-value", text: "2"
    assert_select ".queue__band-count", text: "1", count: 2
    assert_select "tr[data-queue-filter-name=?]", "usb blaster"
  end

  test "averages the time from order to fulfillment per item" do
    Shop::QueueSnapshot::MIN_SAMPLE.times do
      build_order(@listed, aasm_state: "fulfilled", created_at: 10.days.ago,
                           awaiting_periodical_fulfillment_at: 9.days.ago, fulfilled_at: 2.days.ago)
    end

    get queue_path

    assert_response :success
    assert_select "tr[data-queue-filter-name=?]", "usb blaster" do
      assert_select ".queue__cell-number", text: "24 hours"
      assert_select ".queue__cell-number", text: "8 days"
    end
  end

  test "withholds an average until an item has enough fulfilled orders" do
    build_order(@listed, aasm_state: "fulfilled", created_at: 10.days.ago, fulfilled_at: 2.days.ago)

    get queue_path

    assert_response :success
    assert_select "tr[data-queue-filter-name=?]", "usb blaster" do
      assert_select ".queue__cell-number", text: "—"
    end
  end

  test "folds orders for unlisted items into one anonymous row" do
    build_order(@unlisted, aasm_state: "pending", created_at: 1.hour.ago)

    get queue_path

    assert_response :success
    assert_not_includes response.body, "Secret Prize"
    assert_select "tr[data-queue-filter-name=?]", Shop::QueueSnapshot::HIDDEN_ITEM_LABEL.downcase
  end

  test "folds mission-prize-only items into the anonymous row" do
    prize = build_item("Unreleased Trophy", mission_prize_only: true)
    build_order(prize, aasm_state: "pending", created_at: 1.hour.ago)

    get queue_path

    assert_response :success
    assert_not_includes response.body, "Unreleased Trophy"
    assert_select "tr[data-queue-filter-name=?]", Shop::QueueSnapshot::HIDDEN_ITEM_LABEL.downcase
  end

  test "folds accessories that cannot be bought on their own" do
    accessory = build_item("Spare Nozzle", type: "ShopItem::Accessory")
    ShopItemAttachment.create!(parent_item: @listed, accessory_item: accessory)
    accessory.update!(buyable_by_self: false)
    build_order(accessory, aasm_state: "pending", created_at: 1.hour.ago)

    get queue_path

    assert_response :success
    assert_not_includes response.body, "Spare Nozzle"
    assert_select "tr[data-queue-filter-name=?]", Shop::QueueSnapshot::HIDDEN_ITEM_LABEL.downcase
  end

  # A sold-out item still has people waiting on it, so it keeps its own row
  # rather than disappearing into the anonymous one.
  test "still names a disabled item that has orders in the queue" do
    retired = build_item("Sold Out Kit")
    build_order(retired, aasm_state: "pending", created_at: 1.hour.ago)
    retired.update!(enabled: false)

    get queue_path

    assert_response :success
    assert_select "tr[data-queue-filter-name=?]", "sold out kit"
  end

  private

  def build_item(name, type: "ShopItem::ThirdPartyPhysical", **attributes)
    item = ShopItem.new(
      name: name,
      description: "test item",
      ticket_cost: 10,
      type: type,
      enabled: true,
      **attributes
    )
    item.image.attach(io: StringIO.new(PIXEL_PNG), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end

  # Orders are built unvalidated on purpose: the page only reads state and
  # timestamps, and a valid purchase would need a balance, an address and a
  # passing fraud check none of which this page looks at.
  def build_order(item, **attributes)
    order = ShopOrder.new(user: @user, shop_item: item, quantity: 1, **attributes)
    order.save!(validate: false)
    order
  end
end
