# == Schema Information
#
# Table name: shop_categories
#
#  id         :bigint           not null, primary key
#  hub_title  :string           not null
#  position   :integer          default(0), not null
#  slug       :string           not null
#  title      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_shop_categories_on_position  (position)
#  index_shop_categories_on_slug      (slug) UNIQUE
#
require "test_helper"

class ShopCategoryTest < ActiveSupport::TestCase
  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  setup do
    @hardware = ShopCategory.create!(slug: "npl_hw", title: "Hardware", hub_title: "Gadgets")
    @in_cat = build_item("In Category")
    @out_cat = build_item("Out Category")
    ShopItemCategory.create!(shop_item: @in_cat, shop_category: @hardware)
  end

  test "filter keeps items that belong to the category" do
    assert_equal [ @in_cat ], @hardware.filter([ @in_cat, @out_cat ])
  end

  test "filter still works when the join is not preloaded" do
    category = ShopCategory.find(@hardware.id)
    assert_not category.shop_item_categories.loaded?
    assert_equal [ @in_cat ], category.filter([ @in_cat, @out_cat ])
  end

  test "virtual all returns the list unchanged" do
    assert_equal [ @in_cat, @out_cat ], ShopCategory.all_virtual.filter([ @in_cat, @out_cat ])
  end

  test "Categorization.all preloads join rows so hub filter does not query" do
    hardware = Shop::Categorization.all.find { |c| c.slug == "npl_hw" }
    assert hardware.shop_item_categories.loaded?

    queries = []
    callback = lambda do |*args|
      sql = args.last[:sql]
      queries << sql if sql.match?(/shop_item_categories/i) && !sql.match?(/SCHEMA/)
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      assert_equal [ @in_cat ], hardware.filter([ @in_cat, @out_cat ])
    end

    assert_empty queries
  end

  test "Categorization.filter delegates to the matching category" do
    assert_equal [ @in_cat ], Shop::Categorization.filter([ @in_cat, @out_cat ], "npl_hw")
  end

  private

  def build_item(name)
    item = ShopItem.new(
      name: name,
      description: "test item",
      ticket_cost: 10,
      type: "ShopItem::ThirdPartyPhysical",
      enabled: true
    )
    item.image.attach(io: StringIO.new(PIXEL_PNG), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end
end
