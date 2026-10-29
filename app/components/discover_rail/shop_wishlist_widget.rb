# frozen_string_literal: true

module DiscoverRail
  class ShopWishlistWidget < BaseWidget
    register_as :shop_wishlist

    def balance
      context[:user_balance] || 0
    end

    def region
      context[:user_region] || "US"
    end

    def wishlisted_items
      return [] unless user
      @wishlisted_items ||= user.shop_wishlists.includes(shop_item: { image_attachment: :blob }).map(&:shop_item)
                                .tap { |items| ShopItem.preload_sale_units_sold(items) }
    end

    def render?
      user.present?
    end
  end
end
