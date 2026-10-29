require "test_helper"

class ShopHelperTest < ActionView::TestCase
  include ShopHelper

  test "customs_warning_item_type maps US-origin items" do
    assert_equal "us_origin", customs_warning_item_type(ShopItem::WarehouseItem.new)
    assert_equal "us_origin", customs_warning_item_type(ShopItem::HQMailItem.new)
  end

  test "customs_warning_item_type maps UK-origin items" do
    assert_equal "uk_origin", customs_warning_item_type(ShopItem::Inkthreadable.new)
  end

  test "customs_warning_item_type maps unknown-origin items" do
    assert_equal "unknown_origin", customs_warning_item_type(ShopItem::HackClubberItem.new)
  end

  test "customs_warning_item_type maps third-party physical items" do
    assert_equal "third_party", customs_warning_item_type(ShopItem::ThirdPartyPhysical.new)
  end

  test "customs_warning_item_type returns none for items without customs exposure" do
    assert_equal "none", customs_warning_item_type(ShopItem::ThirdPartyDigital.new)
    assert_equal "none", customs_warning_item_type(ShopItem::FreeStickers.new)
  end

  test "customs_warning_item_type prefers a configured source_region" do
    assert_equal "custom_region", customs_warning_item_type(ShopItem::ThirdPartyPhysical.new(source_region: "EU"))
    assert_equal "custom_region", customs_warning_item_type(ShopItem::HackClubberItem.new(source_region: "IN"))
    assert_equal "custom_region", customs_warning_item_type(ShopItem::HQMailItem.new(source_region: "UK"))
  end

  test "customs_warning_item_type ignores source_region on items that cannot configure it" do
    assert_equal "us_origin", customs_warning_item_type(ShopItem::WarehouseItem.new(source_region: "EU"))
  end

  test "customs_warning_message describes each item type's origin" do
    assert_includes customs_warning_message(ShopItem::WarehouseItem.new), "shipped from the United States"
    assert_includes customs_warning_message(ShopItem::HQMailItem.new), "shipped from the United States"
    assert_includes customs_warning_message(ShopItem::Inkthreadable.new), "shipped from the United Kingdom"
    assert_includes customs_warning_message(ShopItem::HackClubberItem.new), "Origin unknown"
  end

  test "customs_warning_message warns about third-party retailers" do
    assert_equal ShopHelper::THIRD_PARTY_CUSTOMS_WARNING, customs_warning_message(ShopItem::ThirdPartyPhysical.new)
    assert_includes ShopHelper::THIRD_PARTY_CUSTOMS_WARNING, "third-party retailer"
  end

  test "customs_warning_message is nil for items without customs exposure" do
    assert_nil customs_warning_message(ShopItem::ThirdPartyDigital.new)
  end

  test "customs_warning_message uses the configured source_region name" do
    message = customs_warning_message(ShopItem::ThirdPartyPhysical.new(source_region: "EU"))

    assert_equal "⚠️ This item is shipped from EU. Customs fees may apply if the destination country is not in EU.", message
  end

  test "customs_warning_source_region only exposes configurable items" do
    assert_equal "EU", customs_warning_source_region(ShopItem::ThirdPartyPhysical.new(source_region: "EU"))
    assert_nil customs_warning_source_region(ShopItem::WarehouseItem.new(source_region: "EU"))
  end
end
