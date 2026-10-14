require "test_helper"

class ShopItem::StickyStreakStickerTest < ActiveSupport::TestCase
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  test "a new sticker is redemption only, so it never shows up for sale" do
    assert build_sticker.mission_prize_only?
  end

  test "the default gives way to an explicit choice" do
    assert_not build_sticker(mission_prize_only: false).mission_prize_only?
  end

  test "it ships through the ordinary letter mail queue" do
    sticker = build_sticker

    assert_kind_of ShopItem::LetterMail, sticker
    assert_equal ShopItem::LetterMail::THESEUS_QUEUE, sticker.class::THESEUS_QUEUE
    assert_equal ShopItem::LetterMail::MAX_ITEMS_PER_LETTER, sticker.class::MAX_ITEMS_PER_LETTER
  end

  test "it is registered everywhere the letter mail type strings are matched" do
    assert_includes ShopItem::LetterMail::TYPES, "ShopItem::StickyStreakSticker"
    assert_includes ShopItem::SELECTABLE_TYPES, "ShopItem::StickyStreakSticker"
    assert_includes Admin::Shop::OrdersController::TOGGLEABLE_ITEM_TYPES, "ShopItem::StickyStreakSticker"
  end

  test "the batch send sweep leaves stickers alone but still takes ordinary letter mail" do
    assert_not_includes Shop::ProcessLetterMailOrdersJob::LETTER_TYPES, "ShopItem::StickyStreakSticker"
    assert_includes Shop::ProcessLetterMailOrdersJob::LETTER_TYPES, "ShopItem::LetterMail"
    assert_includes Shop::ProcessLetterMailOrdersJob::LETTER_TYPES, "ShopItem::NonmachinableLetterMail"
  end

  test "a sticker order awaiting fulfillment is not swept up by the batch job" do
    order = sticker_order

    Shop::ProcessLetterMailOrdersJob.perform_now

    assert_equal "awaiting_periodical_fulfillment", order.reload.aasm_state
  end

  test "a sticker order is still sendable on its own, through the same queue" do
    order = sticker_order

    assert_equal ShopItem::LetterMail::THESEUS_QUEUE, order.shop_item.class::THESEUS_QUEUE
    assert order.shop_item.is_a?(ShopItem::LetterMail), "the per-order send button keys off this"
  end

  private

  def sticker_order
    user = create_user(slack_id: "U-sss", display_name: "sss", verified: true)
    user.update!(has_gotten_free_stickers: true)
    sticker = build_sticker(mission_prize_only: false, enabled: true)
    sticker.save!

    user.shop_orders.create!(shop_item: sticker, quantity: 1, aasm_state: "awaiting_periodical_fulfillment",
                             frozen_address: { "id" => "a", "country" => "US" }, frozen_item_price: 0)
  end

  def build_sticker(**attributes)
    sticker = ShopItem::StickyStreakSticker.new(
      { name: "Day One Sticker", description: "sticker", ticket_cost: 0 }.merge(attributes)
    )
    sticker.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    sticker
  end
end
