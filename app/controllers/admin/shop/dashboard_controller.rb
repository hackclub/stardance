class Admin::Shop::DashboardController < Admin::ApplicationController
  def show
    authorize ShopItem, :index?
    @shop_items = ShopItem.order(created_at: :desc)

    if params[:search].present?
      search_term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%"
      @shop_items = @shop_items.where("name ILIKE ? OR id::text = ?", search_term, params[:search])
    end

    if params[:type].present?
      @shop_items = @shop_items.where(type: params[:type])
    end

    if params[:enabled].present?
      @shop_items = @shop_items.where(enabled: params[:enabled] == "true")
    end

    if params[:carousel].present?
      @shop_items = @shop_items.where(show_in_carousel: params[:carousel] == "true")
    end

    @item_types = ShopItem.distinct.pluck(:type).compact.sort
    @pagy, @shop_items = pagy(@shop_items.includes(:shop_categories))
  end
end
