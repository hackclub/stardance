# == Schema Information
#
# Table name: shop_items
#
#  id                                :bigint           not null, primary key
#  accessory_tag                     :string
#  agh_contents                      :jsonb
#  attached_shop_item_ids            :bigint           default([]), is an Array
#  blocked_countries                 :string           default([]), is an Array
#  buyable_by_self                   :boolean          default(TRUE)
#  default_assigned_user_id_au       :bigint
#  default_assigned_user_id_ca       :bigint
#  default_assigned_user_id_eu       :bigint
#  default_assigned_user_id_in       :bigint
#  default_assigned_user_id_uk       :bigint
#  default_assigned_user_id_us       :bigint
#  default_assigned_user_id_xx       :bigint
#  description                       :string
#  draft                             :boolean          default(FALSE), not null
#  enabled                           :boolean
#  enabled_au                        :boolean
#  enabled_ca                        :boolean
#  enabled_eu                        :boolean
#  enabled_in                        :boolean
#  enabled_uk                        :boolean
#  enabled_until                     :datetime
#  enabled_us                        :boolean
#  enabled_xx                        :boolean
#  hacker_score                      :integer
#  hcb_category_lock                 :string
#  hcb_keyword_lock                  :string
#  hcb_merchant_lock                 :string
#  hcb_one_time_use                  :boolean          default(FALSE)
#  hcb_preauthorization_instructions :text
#  internal_description              :string
#  limited                           :boolean
#  long_description                  :text
#  max_qty                           :integer
#  name                              :string
#  old_prices                        :integer          default([]), is an Array
#  one_per_person_ever               :boolean
#  past_purchases                    :integer          default(0)
#  payout_percentage                 :integer          default(0)
#  required_ships_count              :integer          default(1)
#  required_ships_end_date           :date
#  required_ships_start_date         :date
#  requires_achievement              :string           default([]), is an Array
#  requires_ship                     :boolean          default(FALSE)
#  requires_verification_call        :boolean          default(FALSE), not null
#  sale_percentage                   :integer
#  show_image_in_shop                :boolean          default(FALSE)
#  show_in_carousel                  :boolean
#  site_action                       :integer
#  source_region                     :string
#  special                           :boolean
#  stock                             :integer
#  ticket_cost                       :integer
#  type                              :string
#  unlisted                          :boolean          default(FALSE)
#  unlock_on                         :date
#  usd_cost                          :decimal(, )
#  usd_offset_au                     :decimal(10, 2)
#  usd_offset_ca                     :decimal(10, 2)
#  usd_offset_eu                     :decimal(10, 2)
#  usd_offset_in                     :decimal(10, 2)
#  usd_offset_uk                     :decimal(10, 2)
#  usd_offset_us                     :decimal(10, 2)
#  usd_offset_xx                     :decimal(10, 2)
#  created_at                        :datetime         not null
#  updated_at                        :datetime         not null
#  created_by_user_id                :bigint
#  default_assigned_user_id          :bigint
#  user_id                           :bigint
#
# Indexes
#
#  index_shop_items_on_created_by_user_id        (created_by_user_id)
#  index_shop_items_on_default_assigned_user_id  (default_assigned_user_id)
#  index_shop_items_on_user_id                   (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (default_assigned_user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id)
#
class ShopItem < ApplicationRecord
  has_paper_trail

  include Shop::Regionalizable

  has_ferret_search :name, :description, type: -> { type.demodulize.underscore.humanize }

  before_validation :fix_blacklist
  before_validation :floor_ticket_cost
  before_validation :clean_requires_achievement

  after_commit :refresh_carousel_cache, if: :carousel_relevant_change?
  after_commit :invalidate_shop_page_cache

  RECENTLY_ADDED_WINDOW = 2.weeks
  SHOP_PAGE_CACHE_KEY = "shop_items/shop_page"

  def self.cached_shop_page_data
    Rails.cache.fetch(SHOP_PAGE_CACHE_KEY, expires_in: 5.minutes) do
      buyable = enabled.listed.buyable_standalone.includes(image_attachment: :blob).to_a
      item_ids = buyable.map(&:id)

      reserved_counts = ShopOrder
        .where(shop_item_id: item_ids, aasm_state: %w[pending awaiting_verification awaiting_verification_call awaiting_periodical_fulfillment on_hold fulfilled])
        .group(:shop_item_id).sum(:quantity)

      purchase_counts = ShopOrder
        .where(shop_item_id: item_ids, aasm_state: %w[awaiting_fulfillment fulfilled])
        .group(:shop_item_id).sum(:quantity)

      buyable.each do |item|
        item.instance_variable_set(:@preloaded_reserved_quantity, reserved_counts[item.id] || 0)
        item.instance_variable_set(:@preloaded_purchase_count, purchase_counts[item.id] || 0)
      end

      cutoff = RECENTLY_ADDED_WINDOW.ago
      recently_added = buyable.select { |item| item.created_at >= cutoff }.sort_by(&:created_at).reverse

      { buyable_standalone: buyable, recently_added: recently_added }
    end
  end

  def self.invalidate_shop_page_cache!
    Rails.cache.delete(SHOP_PAGE_CACHE_KEY)
  end

  MANUAL_FULFILLMENT_TYPES = [
    "ShopItem::HCBGrant",
    "ShopItem::HCBPreauthGrant",
    "ShopItem::ThirdPartyPhysical",
    "ShopItem::SpecialFulfillmentItem"
  ].freeze

  scope :shown_in_carousel, -> { where(show_in_carousel: true) }
  scope :manually_fulfilled, -> { where(type: MANUAL_FULFILLMENT_TYPES) }
  scope :enabled, -> { where(enabled: true, draft: [ nil, false ]).where("shop_items.enabled_until IS NULL OR shop_items.enabled_until > ?", Time.current) }
  scope :listed, -> { where(unlisted: [ nil, false ]) }
  scope :buyable_standalone, -> { where.not(type: "ShopItem::Accessory").or(where(buyable_by_self: true)) }
  scope :recently_added, -> { where(created_at: RECENTLY_ADDED_WINDOW.ago..).order(created_at: :desc) }
  scope :drafts, -> { where(draft: true) }
  scope :published, -> { where(draft: [ nil, false ]) }

  belongs_to :seller, class_name: "User", foreign_key: :user_id, optional: true
  belongs_to :created_by, class_name: "User", foreign_key: :created_by_user_id, optional: true
  belongs_to :default_assigned_user, class_name: "User", optional: true
  belongs_to :default_assigned_user_us, class_name: "User", optional: true
  belongs_to :default_assigned_user_eu, class_name: "User", optional: true
  belongs_to :default_assigned_user_uk, class_name: "User", optional: true
  belongs_to :default_assigned_user_ca, class_name: "User", optional: true
  belongs_to :default_assigned_user_au, class_name: "User", optional: true
  belongs_to :default_assigned_user_in, class_name: "User", optional: true
  belongs_to :default_assigned_user_xx, class_name: "User", optional: true

  def default_assignee_for_region(region)
    return default_assigned_user_id unless region.present?

    regional_assignee = send("default_assigned_user_id_#{region.downcase}") rescue nil
    regional_assignee.presence || default_assigned_user_id
  end

  has_one_attached :image do |attachable|
    attachable.variant :carousel_sm,
                       crop_to_content: true,
                       resize_to_limit: [ 160, nil ],
                       format: :webp,
                       preprocessed: true,
                       saver: { strip: true, quality: 75 }

    attachable.variant :carousel_md,
                       crop_to_content: true,
                       resize_to_limit: [ 240, nil ],
                       format: :webp,
                       preprocessed: true,
                       saver: { strip: true, quality: 75 }

    attachable.variant :carousel_lg,
                       crop_to_content: true,
                       resize_to_limit: [ 360, nil ],
                       format: :webp,
                       preprocessed: true,
                       saver: { strip: true, quality: 75 }
  end
  validates :name, :description, :ticket_cost, :type, presence: true
  validates :ticket_cost, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :image, presence: true, on: :create
  validates :required_ships_count, numericality: { only_integer: true, greater_than: 0 }, if: :requires_ship?
  validates :required_ships_start_date, :required_ships_end_date, presence: true, if: :requires_ship?
  validate :is_range_valid, if: :requires_ship?
  validate :validate_achievement_slugs

  has_many :shop_orders, dependent: :restrict_with_error

  def agh_contents=(value)
    if value.is_a?(String) && value.present?
      begin
        super(JSON.parse(value))
      rescue JSON::ParserError
        errors.add(:agh_contents, "is not valid JSON")
        super(nil)
      end
    else
      super(value)
    end
  end

  def is_free?
    self.ticket_cost.zero?
  end
  def on_sale?
    sale_percentage.present? && sale_percentage > 0
  end

  def average_hours_estimated
    return 0 unless ticket_cost.present?
    ticket_cost / (Rails.configuration.game_constants.tickets_per_dollar * Rails.configuration.game_constants.dollars_per_mean_hour)
  end

  def hours_estimated
    average_hours_estimated.to_i
  end

  def fixed_estimate(price)
    return 0 unless price.present? && price > 0
    price / (Rails.configuration.game_constants.tickets_per_dollar * Rails.configuration.game_constants.dollars_per_mean_hour)
  end

  def remaining_stock
    return nil unless limited? && stock.present?

    reserved_quantity = if instance_variable_defined?(:@preloaded_reserved_quantity)
                          @preloaded_reserved_quantity
    else
                          shop_orders.where(aasm_state: %w[pending awaiting_verification awaiting_verification_call awaiting_periodical_fulfillment on_hold fulfilled]).sum(:quantity)
    end
    stock - reserved_quantity
  end

  def out_of_stock?
    limited? && remaining_stock && remaining_stock <= 0
  end

  def current_event_purchases
    if instance_variable_defined?(:@preloaded_purchase_count)
      @preloaded_purchase_count
    else
      shop_orders.where(aasm_state: %w[awaiting_fulfillment fulfilled]).sum(:quantity)
    end
  end

  def display_purchase_count
    c = current_event_purchases
    c > 2 ? c : (past_purchases.to_i > 2 ? past_purchases : nil)
  end

  def new_item? = created_at.present? && created_at > 7.days.ago

  def expired?
    enabled_until.present? && enabled_until <= Time.current
  end

  def available_accessories
    ShopItem::Accessory.where("? = ANY(attached_shop_item_ids)", id).enabled
  end

  def has_accessories?
    available_accessories.exists?
  end

  def meet_ship_require?(user)
    return true unless requires_ship?
    return false unless user.present?

    user.shipped_projects_count_in_range(required_ships_start_date, required_ships_end_date) >= required_ships_count
  end

  def blocked_in_country?(country_code)
    return false unless country_code.present? && blocked_countries.present?
    blocked_countries.include?(country_code.upcase)
  end

  def meet_achievement_require?(user)
    return true unless requires_achievement?
    return false unless user.present?

    requires_achievement.any? do |ach_slug|
      user.earned_achievement?(ach_slug.to_sym)
    end
  end

  def requires_achievement?
    requires_achievement.present?
  end

  def achievement_locked_for?(user)
    requires_achievement? && !meet_achievement_require?(user)
  end

  def required_achievement_objects
    requires_achievement.map { |slug| Achievement.find(slug) }
  end

  private

  def is_range_valid
    return unless required_ships_start_date.present? && required_ships_end_date.present?

    if required_ships_end_date < required_ships_start_date
      errors.add(:required_ships_end_date, "must be after start date")
    end
  end

  def carousel_relevant_change?
    show_in_carousel? || saved_change_to_show_in_carousel?
  end

  def refresh_carousel_cache
    Cache::CarouselPrizesJob.perform_later(force: true)
  end

  def invalidate_shop_page_cache
    self.class.invalidate_shop_page_cache!
  end

  def fix_blacklist
    return unless blocked_countries.present?
    self.blocked_countries = blocked_countries.map(&:upcase).reject(&:blank?).uniq
  end

  def floor_ticket_cost
    self.ticket_cost = ticket_cost.floor if ticket_cost.present?
  end

  def clean_requires_achievement
    if requires_achievement.is_a?(Array)
      self.requires_achievement = requires_achievement.reject(&:blank?)
    end
  end

  def validate_achievement_slugs
    return unless requires_achievement.present?
    invalid = requires_achievement.reject { |s| Achievement.all_slugs.include?(s.to_sym) }
    errors.add(:requires_achievement, "contains invalid slugs: #{invalid.join(', ')}") if invalid.any?
  end
end
