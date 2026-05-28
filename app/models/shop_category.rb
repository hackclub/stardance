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
class ShopCategory < ApplicationRecord
  ALL_SLUG = "all"

  has_many :shop_item_categories, dependent: :destroy
  has_many :shop_items, through: :shop_item_categories

  validates :slug, :title, :hub_title, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/, message: "must be lowercase letters, numbers, or underscores" }

  scope :ordered, -> { order(:position, :id) }

  # "all" is a virtual category — it doesn't have its own row, it just means
  # "don't filter." Callers ask for `find_by_slug("all")` and we hand back a
  # synthetic record so the controller/view don't special-case it everywhere.
  def self.all_virtual
    new(slug: ALL_SLUG, title: "All", hub_title: "All", position: -1).tap(&:readonly!)
  end

  def self.find_by_slug(slug)
    return all_virtual if slug.to_s == ALL_SLUG

    find_by(slug: slug)
  end

  def virtual_all?
    slug == ALL_SLUG && new_record?
  end

  def filter(items)
    return items if virtual_all?

    item_ids = shop_item_ids
    items.select { |it| item_ids.include?(it.id) }
  end
end
