require "test_helper"
require "base64"

class ShipTickerTest < ActiveSupport::TestCase
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @owner = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "ticker#{SecureRandom.hex(4)}", verified: true)
  end

  test "lists public ships newest first" do
    older = create_ship(title: "Older", hours: 2.5, shipped_at: 2.days.ago)
    newer = create_ship(title: "Newer", hours: 10, shipped_at: 1.hour.ago)

    ticker = ShipTicker.new

    assert_equal [ newer.project.id, older.project.id ], ticker.entries.map(&:project_id)
    assert_equal "Newer", ticker.entries.first.project_title
    assert_equal @owner.display_name, ticker.entries.first.author
  end

  test "leaves out ships the public can't see" do
    create_ship(title: "Rejected", status: "rejected")
    create_ship(title: "Misfiled", status: "misfiled")
    create_ship(title: "No hours", hours: 0)
    create_ship(title: "Deleted").project.soft_delete!
    create_ship(title: "Unverified", user: create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "unv#{SecureRandom.hex(4)}"))
    banned = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "ban#{SecureRandom.hex(4)}", verified: true)
    create_ship(title: "Banned", user: banned)
    banned.update!(banned: true)

    assert ShipTicker.new.empty?
  end

  test "mixes in a purchase after every two ships as a down" do
    3.times { |i| create_ship(title: "Ship #{i}", shipped_at: i.hours.ago) }
    create_order(item: create_item(name: "Pi"), price: 600, quantity: 2)
    create_order(item: create_item(name: "Secret", unlisted: true))
    create_order(item: create_item(name: "Refunded")).update_columns(aasm_state: "refunded")

    entries = ShipTicker.new.entries

    assert_equal [ ShipTicker::Ship, ShipTicker::Ship, ShipTicker::Purchase, ShipTicker::Ship ], entries.map(&:class)
    assert_equal [ "Pi", 1200 ], [ entries.third.item_name, entries.third.stardust ]
  end

  test "is empty without ships even when people are shopping" do
    create_order(item: create_item(name: "Pi"))

    assert ShipTicker.new.empty?
  end

  private

  def create_item(name:, unlisted: false)
    item = ShopItem.new(name: name, description: "d", ticket_cost: 50, type: "ShopItem::ThirdPartyPhysical", enabled: true, unlisted: unlisted)
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end

  def create_order(item:, price: 50, quantity: 1)
    order = ShopOrder.new(user: @owner, shop_item: item, quantity: quantity, frozen_item_price: price, frozen_address: { "country" => "US" })
    order.save!(validate: false)
    order
  end

  def create_ship(title:, hours: 4, status: "approved", shipped_at: Time.current, user: @owner)
    project = Project.create!(title: title)
    Project::Membership.create!(project: project, user: user, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true, certification_status: status)
    post = Post.create!(project: project, user: user, postable: ship_event, created_at: shipped_at, updated_at: shipped_at)
    ship_event.update_columns(hours_at_ship: hours)
    post
  end
end
