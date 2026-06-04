class ShopItemCardComponent < ViewComponent::Base
  include MarkdownHelper

  CTA_MODES = %i[order tutorial_buy tutorial_verify].freeze

  # JS to pop the shared verify modal (mounted in the layout for unverified
  # users). Used when a tutorial pick's gate is "verify your identity" — we
  # surface the popup in place instead of routing to a separate screen.
  OPEN_VERIFY_MODAL = "document.getElementById('idv-verify-modal')?.showModal()".freeze

  attr_reader :item_id, :name, :description, :hours, :price, :image_url, :item_type, :balance, :enabled_regions, :regional_price, :logged_in, :tutorial_spotlight, :cta_mode, :remaining_stock, :limited, :on_sale, :sale_percentage, :original_price, :created_at, :show_bow, :show_time_ago, :purchase_count, :is_new, :enabled_until, :locked_by_achievement, :required_achievement_names, :required_achievement_hints, :mission_locked, :unlocking_mission_names, :wishlisted

  def initialize(item_id:, name:, description:, hours:, price:, image_url:, item_type: nil, balance: nil, enabled_regions: [], regional_price: nil, logged_in: true, interactive: true, tutorial_spotlight: false, cta_mode: :order, remaining_stock: nil, limited: false, on_sale: false, sale_percentage: nil, original_price: nil, created_at: nil, show_bow: false, show_time_ago: false, purchase_count: nil, is_new: false, enabled_until: nil, locked_by_achievement: false, required_achievement_names: [], required_achievement_hints: [], mission_locked: false, unlocking_mission_names: [], wishlisted: false)
    @item_id = item_id
    @name = name
    @description = description
    @hours = hours
    @price = price
    @image_url = image_url
    @item_type = item_type
    @balance = balance
    @enabled_regions = enabled_regions
    @regional_price = regional_price || price
    @logged_in = logged_in
    @tutorial_spotlight = tutorial_spotlight
    @cta_mode = CTA_MODES.include?(cta_mode) ? cta_mode : :order
    @remaining_stock = remaining_stock
    @limited = limited
    @on_sale = on_sale
    @sale_percentage = sale_percentage
    @original_price = original_price
    @created_at = created_at
    @show_bow = show_bow
    @show_time_ago = show_time_ago
    @purchase_count = purchase_count
    @is_new = is_new
    @enabled_until = enabled_until
    @locked_by_achievement = locked_by_achievement
    @required_achievement_names = required_achievement_names
    @required_achievement_hints = required_achievement_hints
    @mission_locked = mission_locked
    @unlocking_mission_names = unlocking_mission_names
    @wishlisted = wishlisted
  end

  def lock_overlay_html
    return "".html_safe unless locked_by_achievement || mission_locked

    helpers.content_tag(:div, "🔒", class: "shop-item-card__lock-overlay")
  end

  def mission_lock_html
    return "".html_safe unless mission_locked && unlocking_mission_names.any?

    sentence = unlocking_mission_names.to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
    helpers.content_tag(:div, "Unlocked by completing #{sentence}", class: "shop-item-card__mission-requirement")
  end

  def achievement_requirement_html
    return "".html_safe unless locked_by_achievement && required_achievement_names.any?

    sentence = required_achievement_names.to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
    children = [ helpers.content_tag(:div, "Requires: #{sentence}", class: "shop-item-card__achievement-names") ]
    if required_achievement_hints.any?
      children << helpers.content_tag(:div, required_achievement_hints.first, class: "shop-item-card__achievement-hints")
    end
    helpers.content_tag(:div, helpers.safe_join(children), class: "shop-item-card__achievement-requirement")
  end

  def time_ago_text
    return nil unless created_at && show_time_ago
    helpers.time_ago_in_words(created_at) + " ago"
  end

  def order_url
    helpers.shop_item_path(item_id)
  end

  def display_price
    @regional_price
  end

  def categories
    return [] unless item_type
    cats = []
    case item_type
    when "ShopItem::HCBGrant", "ShopItem::HCBPreauthGrant"
      cats << "Grants" << "Digital"
    when "ShopItem::WarehouseItem", "ShopItem::HQMailItem", "ShopItem::LetterMail", "ShopItem::FreeStickers"
      cats << "HQ"
    when "ShopItem::ThirdPartyDigital"
      cats << "Digital"
    when "ShopItem::ThirdPartyPhysical", "ShopItem::SpecialFulfillmentItem"
      cats << "Locally Fulfilled"
    when "ShopItem::HackClubberItem"
      cats << "Made by Hack Clubbers"
    end
    cats
  end

  def out_of_stock?
    limited && remaining_stock.present? && remaining_stock <= 0
  end

  def low_stock?
    limited && remaining_stock.present? && remaining_stock > 0 && remaining_stock <= 5
  end

  def show_stock_indicator?
    limited && remaining_stock.present? && remaining_stock <= 10
  end

  # CTA buttons now show the item's Stardust cost in place of "Buy now" /
  # "Order now". Free items read "Free" and skip the icon so the button isn't
  # an awkward "✦ 0".
  def cta_price_label
    return "Free" if display_price.to_i.zero?
    helpers.number_to_currency(display_price, precision: 0).delete("$")
  end

  def cta_price_icon
    return nil if display_price.to_i.zero?
    "icons/stardust.png"
  end
end
