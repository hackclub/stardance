require "test_helper"

class Shop::ProcessLetterMailOrdersJobTest < ActiveJob::TestCase
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze
  ADDRESS = { "id" => "a", "country" => "US" }.freeze

  test "streak and shop stickers for one person share envelopes, lowest numbers first, 11 to an envelope" do
    user = create_user(slack_id: "U-sweep", display_name: "sweep", verified: true)
    user.update!(has_gotten_free_stickers: true)
    streak = (1..12).to_a.reverse.map { |n| order_for(user, item(ShopItem::StickyStreakSticker, "Sticky Streak ##{n}")) }
    weekly = order_for(user, item(ShopItem::LetterMail, "Weekly Sticker #4"))

    letters = []
    TheseusService.stub(:create_letter_v1, ->(_queue, data) { letters << data; { id: "ltr!#{letters.size}" } }) do
      Shop::ProcessLetterMailOrdersJob.perform_now
    end

    assert_equal [ (1..11).map { |n| "1x Sticky Streak ##{n}" }, [ "1x Sticky Streak #12", "1x Weekly Sticker #4" ] ],
                 letters.map { |l| l[:rubber_stamps].split("\n") }
    assert (streak + [ weekly ]).all? { |o| o.reload.fulfilled? }
  end

  private

  def item(klass, name)
    record = klass.new(name: name, description: name, ticket_cost: 0, enabled: true, mission_prize_only: false)
    record.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    record.save!
    record
  end

  def order_for(user, shop_item)
    user.shop_orders.create!(shop_item: shop_item, quantity: 1, aasm_state: "awaiting_periodical_fulfillment",
                             frozen_address: ADDRESS, frozen_item_price: 0)
  end
end
