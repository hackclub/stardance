module ShopHelper
  PHYSICAL_ITEMS_WITH_CUSTOMS = %w[
    ShopItem::WarehouseItem
    ShopItem::HQMailItem
    ShopItem::HackClubberItem
    ShopItem::ThirdPartyPhysical
    ShopItem::Inkthreadable
  ].freeze

  ITEMS_WITH_CONFIGURABLE_SOURCE_REGION = %w[
    ShopItem::HackClubberItem
    ShopItem::ThirdPartyDigital
    ShopItem::ThirdPartyPhysical
    ShopItem::HQMailItem
  ].freeze

  THIRD_PARTY_CUSTOMS_WARNING = "⚠️ This item is ordered from a third-party retailer and may ship from another country. " \
    "Customs or import fees may apply and are the recipient's responsibility.".freeze

  def customs_warning_message(shop_item)
    if shop_item.source_region.present? && ITEMS_WITH_CONFIGURABLE_SOURCE_REGION.include?(shop_item.type)
      region_name = Shop::Regionalizable::REGIONS.dig(shop_item.source_region, :name) || shop_item.source_region
      return "⚠️ This item is shipped from #{region_name}. Customs fees may apply if the destination country is not in #{region_name}."
    end

    case shop_item.type
    when "ShopItem::WarehouseItem"
      "⚠️ This item is shipped from the United States. Customs fees may apply if the destination country is not the United States."
    when "ShopItem::HQMailItem"
      "⚠️ This item is shipped from the United States. Customs fees may apply if the destination country is not the United States."
    when "ShopItem::HackClubberItem"
      "⚠️ Origin unknown - Customs fees may apply depending on destination country. Check the description for more details."
    when "ShopItem::Inkthreadable"
      "⚠️ This item is shipped from the United Kingdom. Customs fees may apply if the destination country is not the United Kingdom."
    when "ShopItem::ThirdPartyPhysical"
      THIRD_PARTY_CUSTOMS_WARNING
    end
  end

  def item_requires_address?(shop_item)
    PHYSICAL_ITEMS_WITH_CUSTOMS.include?(shop_item.type) || shop_item.type == "ShopItem::FreeStickers"
  end

  def is_warehouse_item?(shop_item)
    shop_item.type == "ShopItem::WarehouseItem"
  end

  def customs_warning_item_type(shop_item)
    if shop_item.source_region.present? && ITEMS_WITH_CONFIGURABLE_SOURCE_REGION.include?(shop_item.type)
      return "custom_region"
    end

    case shop_item.type
    when "ShopItem::WarehouseItem", "ShopItem::HQMailItem"
      "us_origin"
    when "ShopItem::Inkthreadable"
      "uk_origin"
    when "ShopItem::HackClubberItem"
      "unknown_origin"
    when "ShopItem::ThirdPartyPhysical"
      "third_party"
    else
      "none"
    end
  end

  def customs_warning_source_region(shop_item)
    shop_item.source_region if ITEMS_WITH_CONFIGURABLE_SOURCE_REGION.include?(shop_item.type)
  end

  # Renders a tracking code as a link to where it can be tracked, or as plain
  # text when it has nowhere to link (see TrackingLink.for's `universal`).
  def tracking_link_tag(code_or_link, universal: true)
    link = code_or_link.is_a?(TrackingLink) ? code_or_link : TrackingLink.for(code_or_link, universal: universal)
    return if link.nil?
    return link.label if link.url.nil?

    link_to link.label, link.url, target: "_blank", rel: "noopener noreferrer"
  end

  private

  def country_name_from_code(code)
    return code unless code.present?
    country = ISO3166::Country.new(code)
    country ? (country.common_name.presence || country.iso_short_name) : code
  end
end
