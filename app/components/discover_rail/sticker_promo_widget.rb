# frozen_string_literal: true

module DiscoverRail
  class StickerPromoWidget < BaseWidget
    register_as :sticker_promo

    def render?
      user.present? && user.onboarded? && StickerPromo.active?
    end

    def deadline_iso
      StickerPromo.deadline_iso
    end

    def eligible?
      user.projects.where("shipped_at >= ?", StickerPromo.window_start).exists?
    end
  end
end
