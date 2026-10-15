require "test_helper"

# The shop intro lets a user pick free stickers *or* the free "nothing" item,
# and they only ever get one of the two.
class ShopOrderShopIntroTest < ActiveSupport::TestCase
  include UserFactory

  setup do
    @user = create_user(slack_id: "u-intro", display_name: "introducer")
    @nothing = build_intro_item("ShopItem::TutorialNothing", "Nothing")
    @stickers = build_intro_item("ShopItem::FreeStickers", "Free Stickers")
    @address = { "country" => "US", "phone_number" => "+15555550123", "primary" => true }
  end

  test "the first shop intro item can be ordered" do
    order = new_order(@nothing)

    assert order.save, order.errors.full_messages.to_sentence
  end

  test "a second shop intro item is rejected once one has been ordered" do
    new_order(@nothing).save!

    order = new_order(@stickers)

    assert_not order.save
    assert_includes order.errors[:base], "You've already claimed your free shop intro item."
  end

  test "the same shop intro item can't be ordered twice" do
    new_order(@nothing).save!

    order = new_order(@nothing)

    assert_not order.save
    assert_includes order.errors[:base], "You've already claimed your free shop intro item."
  end

  test "a rejected shop intro order doesn't block claiming one again" do
    first = new_order(@nothing)
    first.save!
    first.update_columns(aasm_state: "rejected")

    order = new_order(@nothing)

    assert order.save, order.errors.full_messages.to_sentence
  end

  private

  def new_order(item)
    @user.shop_orders.new(shop_item: item, quantity: 1, frozen_address: @address, aasm_state: "pending")
  end

  def build_intro_item(type, name)
    item = ShopItem.new(name: name, description: "Shop intro item", ticket_cost: 0, type: type, enabled: true)
    item.image.attach(
      io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")),
      filename: "px.png",
      content_type: "image/png"
    )
    item.save!
    item
  end
end
