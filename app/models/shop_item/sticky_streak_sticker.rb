# The sticker a Sticky Streak day pays out. Ships as ordinary letter mail; the
# separate type exists so these are filterable in the admin queues and reports,
# and so a reward sticker is not purchasable by accident.
class ShopItem::StickyStreakSticker < ShopItem::LetterMail
  # Earned by keeping a streak, never bought, so new stickers start locked to
  # redemption. Overridable in the item form for a sticker you also want to
  # sell.
  attribute :mission_prize_only, :boolean, default: true
end
