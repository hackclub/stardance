# frozen_string_literal: true

module DiscoverRail
  class StickerPromoWidget < BaseWidget
    register_as :sticker_promo

    def render?
      user.present? && user.onboarded? && StickerPromo.active? && !claimed?
    end

    def deadline_iso
      StickerPromo.deadline_iso
    end

    def shop_item_id
      StickerPromo.shop_item_id
    end

    def eligible?
      user.projects.where("shipped_at >= ?", StickerPromo.window_start).exists?
    end

    # Rejected or refunded orders don't count, so the card comes back for
    # anyone who still needs to claim.
    def claimed?
      shop_item_id.present? && user.shop_orders.worth_counting.where(shop_item_id: shop_item_id).exists?
    end
  end
end
