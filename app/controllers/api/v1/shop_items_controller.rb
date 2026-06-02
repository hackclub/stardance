class Api::V1::ShopItemsController < Api::BaseController
  include ApiAuthenticatable

  def index
    return unless (limit = api_limit)

    items = ShopItem.enabled.listed
                    .includes(:shop_categories, image_attachment: :blob)
                    .order(created_at: :desc)

    if params[:category].present?
      items = items.joins(:shop_categories).where(shop_categories: { slug: params[:category] })
    end

    @pagy, @items = pagy(items, limit: limit)
    @user_region = current_api_user.shop_region || "XX"
  end

  def show
    @item = ShopItem.enabled.listed
                    .includes(:shop_categories, :shop_item_modifiers, image_attachment: :blob)
                    .find(params[:id])
    @user_region = current_api_user.shop_region || "XX"
  end
end
