require "test_helper"
require "ostruct"

class TheseusServiceTest < ActiveSupport::TestCase
  test "create_letter stamps items in natural order, not order id or text order" do
    names = [ "Weekly Sticker #4", "Sticky Streak #10", "Sticky Streak #2", "Sticky Streak #1", "buku buku stickers" ]

    assert_equal [
      "1x buku buku stickers",
      "1x Sticky Streak #1",
      "1x Sticky Streak #2",
      "1x Sticky Streak #10",
      "1x Weekly Sticker #4"
    ], stamped_lines(names)
  end

  private

  def stamped_lines(names)
    orders = names.each_with_index.map do |name, index|
      OpenStruct.new(
        id: index + 1,
        quantity: 1,
        user_id: 1,
        user: OpenStruct.new(email: "orpheus@example.com"),
        frozen_address: {},
        shop_item_id: index + 1,
        shop_item: OpenStruct.new(name: name),
        selected_modifiers: []
      )
    end

    payload = nil
    capture = ->(_queue, data) { payload = data; { id: "ltr!test" } }
    TheseusService.stub(:create_letter_v1, capture) { TheseusService.create_letter(orders, queue: "stardance-orders") }

    payload[:rubber_stamps].split("\n")
  end
end
