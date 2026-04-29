# == Schema Information
#
# Table name: shop_orders
#
#  id                                 :bigint           not null, primary key
#  aasm_state                         :string
#  accessory_ids                      :bigint           default([]), is an Array
#  awaiting_periodical_fulfillment_at :datetime
#  external_ref                       :string
#  frozen_address_ciphertext          :text
#  frozen_item_price                  :decimal(6, 2)
#  fulfilled_at                       :datetime
#  fulfilled_by                       :string
#  fulfillment_cost                   :decimal(6, 2)
#  internal_notes                     :text
#  internal_rejection_reason          :text
#  joe_case_url                       :string
#  on_hold_at                         :datetime
#  quantity                           :integer
#  region                             :string(2)
#  rejected_at                        :datetime
#  rejection_reason                   :string
#  tracking_number                    :string
#  created_at                         :datetime         not null
#  updated_at                         :datetime         not null
#  assigned_to_user_id                :bigint
#  fraud_related_project_id           :bigint
#  fulfillment_payout_line_id         :bigint
#  parent_order_id                    :bigint
#  shop_card_grant_id                 :bigint
#  shop_item_id                       :bigint           not null
#  user_id                            :bigint           not null
#  warehouse_package_id               :bigint
#
# Indexes
#
#  idx_shop_orders_aasm_state_created_at_desc       (aasm_state,created_at DESC)
#  idx_shop_orders_item_state_qty                   (shop_item_id,aasm_state,quantity)
#  idx_shop_orders_stock_calc                       (shop_item_id,aasm_state)
#  idx_shop_orders_user_item_state                  (user_id,shop_item_id,aasm_state)
#  idx_shop_orders_user_item_unique                 (user_id,shop_item_id)
#  index_shop_orders_on_assigned_to_user_id         (assigned_to_user_id)
#  index_shop_orders_on_fulfillment_payout_line_id  (fulfillment_payout_line_id)
#  index_shop_orders_on_parent_order_id             (parent_order_id)
#  index_shop_orders_on_region                      (region)
#  index_shop_orders_on_shop_card_grant_id          (shop_card_grant_id)
#  index_shop_orders_on_shop_item_id                (shop_item_id)
#  index_shop_orders_on_user_id                     (user_id)
#  index_shop_orders_on_warehouse_package_id        (warehouse_package_id)
#
# Foreign Keys
#
#  fk_rails_...  (assigned_to_user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (fulfillment_payout_line_id => fulfillment_payout_lines.id)
#  fk_rails_...  (parent_order_id => shop_orders.id)
#  fk_rails_...  (shop_item_id => shop_items.id)
#  fk_rails_...  (user_id => users.id)
#  fk_rails_...  (warehouse_package_id => shop_warehouse_packages.id)
#
class ShopOrder < ApplicationRecord
  has_paper_trail ignore: [ :frozen_address_ciphertext ]

  include AASM
  include Ledgerable

  belongs_to :user
  belongs_to :shop_item
  belongs_to :shop_card_grant, optional: true
  belongs_to :parent_order, class_name: "ShopOrder", optional: true
  has_many :accessory_orders, class_name: "ShopOrder", foreign_key: :parent_order_id, dependent: :destroy
  has_many :reviews, class_name: "ShopOrderReview", dependent: :destroy
  belongs_to :warehouse_package, class_name: "ShopWarehousePackage", optional: true
  belongs_to :assigned_to_user, class_name: "User", optional: true
  belongs_to :fulfillment_payout_line, optional: true
  belongs_to :fraud_related_project, class_name: "Project", optional: true, foreign_key: :fraud_related_project_id, inverse_of: false

  # has_many :payouts, as: :payable, dependent: :destroy

  # Encrypt frozen_address using Lockbox
  has_encrypted :frozen_address, type: :json

  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }, on: :create
  validates :frozen_address, presence: true, on: :create
  validate :check_one_per_person_ever_limit, on: :create
  validate :check_max_quantity_limit, on: :create
  validate :check_user_balance, on: :create
  validate :check_regional_availability, on: :create
  validate :check_free_stickers_requirement, on: :create
  validate :check_devlog_for_free_stickers, on: :create
  validate :check_stock, on: :create
  validate :check_ship_requirement, on: :create
  validate :check_achievement_requirement, on: :create

  validates :internal_rejection_reason, presence: true, if: :rejected?
  validates :fraud_related_project_id, presence: true, if: :rejected?
  validate :fraud_related_project_exists, if: -> { fraud_related_project_id.present? }

  after_create :create_negative_payout
  after_create :assign_default_user
  after_create :notify_amber_if_verification_call_required
  after_create :hold_if_usps_suspended
  before_create :freeze_item_price
  before_create :set_region_from_address
  after_commit :notify_user_of_status_change, if: :saved_change_to_aasm_state?
  # after_save :notify_assigned_user, if: :saved_change_to_assigned_to_user_id?

  scope :worth_counting, -> { where.not(aasm_state: %w[rejected refunded]) }
  scope :real, -> { without_item_type("ShopItem::FreeStickers") }
  scope :manually_fulfilled, -> { joins(:shop_item).merge(ShopItem.where(type: ShopItem::MANUAL_FULFILLMENT_TYPES)) }
  scope :with_item_type, ->(item_type) { joins(:shop_item).where(shop_items: { type: item_type.to_s }) }
  scope :without_item_type, ->(item_type) { joins(:shop_item).where.not(shop_items: { type: item_type.to_s }) }

  DIGITAL_FULFILLMENT_TYPES = %w[
    ShopItem::HCBGrant
    ShopItem::HCBPreauthGrant
    ShopItem::ThirdPartyDigital
    ShopItem::WarehouseItem
    ShopItem::FreeStickers
    ShopItem::PileOfStickersItem
    ShopItem::SillyItemType
  ].freeze

  DIGITAL_ITEM_TYPES = %w[
    ShopItem::HCBGrant
    ShopItem::HCBPreauthGrant
    ShopItem::ThirdPartyDigital
  ]

  def full_name
    "#{user.display_name}'s order for #{quantity} #{shop_item.name.pluralize(quantity)}"
  end

  def can_view_address?(viewer)
    return false unless viewer

    return true if viewer.admin?

    return false if DIGITAL_FULFILLMENT_TYPES.include?(shop_item.type)

    # Fulfillment person can see addresses in their assigned regions
    if viewer.fulfillment_person?
      return true unless viewer.has_regions?
      return viewer.has_region?(region)
    end

    # Fraud dept + fulfillment person can see addresses
    return true if viewer.fraud_dept? && viewer.fulfillment_person?

    # this makes it so sellers for items can see addresses for their items
    return true if shop_item.user_id == viewer.id && shop_item.type == "ShopItem::HackClubberItem"

    false
  end

  def decrypted_address_for(viewer)
    return nil unless can_view_address?(viewer)

    # Log the access
    PaperTrail::Version.create!(
      item_type: "ShopOrder",
      item_id: id,
      event: "address_access",
      whodunnit: viewer.id,
      object_changes: {
        accessed_at: Time.current,
        user_id: viewer.id,
        order_id: id,
        reason: "address_decryption"
      }.to_yaml
    )

    frozen_address
  end

  aasm timestamps: true do
    # Normal states
    state :pending, initial: true
    state :awaiting_verification
    state :awaiting_verification_call
    state :awaiting_periodical_fulfillment
    state :fulfilled

    # Exception states
    state :rejected
    state :on_hold
    state :refunded

    event :queue_for_verification do
      transitions from: :pending, to: :awaiting_verification
    end

    event :queue_for_verification_call do
      transitions from: :pending, to: :awaiting_verification_call
    end

    event :queue_for_fulfillment do
      transitions from: %i[pending awaiting_verification_call], to: :awaiting_periodical_fulfillment
      after do
        assign_default_user
      end
    end

    event :mark_rejected do
      transitions from: %i[pending awaiting_verification awaiting_verification_call awaiting_periodical_fulfillment on_hold], to: :rejected
      before do |rejection_reason|
        self.rejection_reason = rejection_reason
      end
      after do
        create_refund_payout
      end
    end

    event :mark_fulfilled do
      transitions to: :fulfilled
      before do |external_ref = nil, fulfillment_cost = nil, fulfilled_by = nil|
        self.external_ref = external_ref
        self.fulfillment_cost = fulfillment_cost if fulfillment_cost
        self.fulfilled_by = fulfilled_by if fulfilled_by
      end
      after do
        mark_stickers_received if shop_item.is_a?(ShopItem::FreeStickers)
      end
    end

    event :place_on_hold do
      transitions from: %i[pending awaiting_verification awaiting_verification_call awaiting_periodical_fulfillment], to: :on_hold
    end

    event :take_off_hold do
      transitions from: :on_hold, to: :pending
    end

    event :refund do
      transitions from: %i[pending awaiting_verification awaiting_verification_call awaiting_periodical_fulfillment fulfilled], to: :refunded
      after do
        create_refund_payout
      end
    end
  end

  def digital?
    DIGITAL_ITEM_TYPES.include?(shop_item.type)
  end

  def grant?
    shop_item.is_a?(ShopItem::HCBGrant) || shop_item.is_a?(ShopItem::HCBPreauthGrant)
  end

  def topup_url
    return nil unless grant?

    "https://ui3.hcb.hackclub.com/donations/start/stardance?email=#{user.email}&message=#{}"
  end

  HIGH_VALUE_THRESHOLD = 2000

  def total_cost
    frozen_item_price * quantity
  end

  def accessory_orders_total_cost
    accessory_orders.sum(Arel.sql("frozen_item_price * quantity"))
  end

  def total_cost_with_accessories
    total_cost + (accessory_orders_total_cost || 0)
  end

  def high_value?
    frozen_item_price > HIGH_VALUE_THRESHOLD ||
      total_cost > HIGH_VALUE_THRESHOLD ||
      total_cost_with_accessories > HIGH_VALUE_THRESHOLD
  end

  def requires_additional_review?
    high_value? && reviews.count < 2
  end

  def approve!
    shop_item.fulfill!(self) if shop_item.respond_to?(:fulfill!)
  end

  def mark_stickers_received
    user.update(has_gotten_free_stickers: true)
  end

  def get_agh_contents = shop_item.get_agh_contents(self)

  def notify_user_of_status_change
    return unless user.slack_id.present?

    # Don't notify the user when an order is placed on hold — they shouldn't know
    return if aasm_state == "on_hold"

    template = case aasm_state
    when "rejected" then "notifications/shop_orders/rejected"
    when "awaiting_verification" then "notifications/shop_orders/awaiting_verification"
    when "awaiting_verification_call" then "notifications/shop_orders/awaiting_verification_call"
    when "awaiting_periodical_fulfillment" then "notifications/shop_orders/awaiting_fulfillment"
    when "fulfilled" then "notifications/shop_orders/fulfilled"
    else "notifications/shop_orders/default"
    end

    SendSlackDmJob.perform_later(
      user.slack_id,
      nil,
      blocks_path: template,
      locals: { order: self }
    )
  end

  private

  def freeze_item_price
    return unless shop_item
    return if frozen_item_price.present?

    # Use price_for_region which applies sale discounts and regional pricing
    order_region = region.presence || Shop::Regionalizable.country_to_region(frozen_address&.dig("country"))
    self.frozen_item_price = shop_item.price_for_region(order_region || "XX")
  end

  def check_one_per_person_ever_limit
    return unless shop_item&.one_per_person_ever?

    if quantity && quantity > 1
      errors.add(:quantity, "can only be 1 for #{shop_item.name} (once per person item).")
      return
    end

    existing_order = user.shop_orders.joins(:shop_item).where(shop_item: shop_item).worth_counting
    existing_order = existing_order.where.not(id: id) if persisted?

    if existing_order.exists?
      errors.add(:base, "You can only order #{shop_item.name} once per person.")
    end
  end

  def check_max_quantity_limit
    return unless shop_item&.max_qty && quantity

    if quantity > shop_item.max_qty
      errors.add(:quantity, "cannot exceed #{shop_item.max_qty} for this item.")
    end
  end

  def check_user_balance
    return unless frozen_item_price&.positive? && quantity.present?

    total_cost_for_validation = frozen_item_price * quantity
    if user&.balance&.< total_cost_for_validation
      shortage = total_cost_for_validation - (user.balance || 0)
      errors.add(:base, "Insufficient balance. You need #{shortage} more tickets.")
    end
  end

  USPS_SUSPENDED_COUNTRIES = %w[
    AM AE BH DJ DZ ER IL IQ IR KW LY MG OM PK QA SC SY TZ
  ].freeze

  USPS_SUSPENSION_EXEMPT_TYPES = %w[
    ShopItem::HCBGrant
    ShopItem::HCBPreauthGrant
    ShopItem::ThirdPartyDigital
    ShopItem::SillyItemType
    ShopItem::SpecialFulfillmentItem
  ].freeze

  def check_regional_availability
    return unless shop_item.present? && frozen_address.present?

    address_country = frozen_address["country"]
    return unless address_country.present?

    if USPS_SUSPENDED_COUNTRIES.include?(address_country.upcase) && !USPS_SUSPENSION_EXEMPT_TYPES.include?(shop_item.type)
      errors.add(:base, "Orders to this country are currently suspended due to USPS service restrictions.")
      return
    end

    if shop_item.blocked_countries&.include?(address_country.upcase)
      errors.add(:base, "This item cannot be shipped to that country due to logistical constraints.")
      return
    end

    address_region = Shop::Regionalizable.country_to_region(address_country)

    # Allow items enabled for the address region OR for XX (Rest of World)
    unless shop_item.enabled_in_region?(address_region) || shop_item.enabled_in_region?("XX")
      errors.add(:base, "This item is not available for shipping to #{address_country}.")
    end
  end

  def check_free_stickers_requirement
    return if Rails.env.development?
    return if user&.has_gotten_free_stickers?
    return if shop_item.is_a?(ShopItem::FreeStickers)
    return if user.shop_orders.joins(:shop_item).where(shop_items: { type: "ShopItem::FreeStickers" }).worth_counting.exists?

    errors.add(:base, "You must order the Free Stickers first before ordering other items!")
  end

  def check_devlog_for_free_stickers
    return if Rails.env.development?
    return unless shop_item.is_a?(ShopItem::FreeStickers)
    return if Post.where(user: user, postable_type: "Post::Devlog").exists?

    errors.add(:base, "You must post at least one devlog before ordering free stickers!")
  end

  def check_stock
    return unless shop_item&.limited? && shop_item&.stock.present?

    remaining = shop_item.remaining_stock
    return unless remaining.present?

    if remaining <= 0
      errors.add(:base, "#{shop_item.name} is out of stock.")
    elsif quantity.present? && quantity > remaining
      errors.add(:base, "Only #{remaining} #{shop_item.name.pluralize(remaining)} left in stock.")
    end
  end

  def check_ship_requirement
    return unless shop_item&.requires_ship?
    return if shop_item.meet_ship_require?(user)

    s = shop_item.required_ships_start_date.strftime("%B %d, %Y")
    e = shop_item.required_ships_end_date.strftime("%B %d, %Y")
    c = shop_item.required_ships_count

    errors.add(:base, "You must have shipped at least #{c} #{'project'.pluralize(c)} between #{s} and #{e} to purchase this item.")
  end

  def check_achievement_requirement
    return unless shop_item&.requires_achievement?
    return if shop_item.meet_achievement_require?(user)

    n = shop_item.requires_achievement.map { |s| Achievement.find(s).name }
    msg = n.size == 1 ? "the \"#{n.first}\" achievement" : "one of the \"#{n.to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')}\" achievements"
    errors.add(:base, "You must earn #{msg} to purchase this item.")
  end

  def create_negative_payout
    return unless frozen_item_price.present? && frozen_item_price > 0 && quantity.present?

    user.ledger_entries.create!(
      amount: -total_cost,
      reason: "Shop order of #{shop_item.name.pluralize(quantity)}",
      created_by: "System",
      ledgerable: self
    )
  end

  def create_refund_payout
    return unless frozen_item_price.present? && frozen_item_price > 0 && quantity.present?
    return if shop_item.is_a?(ShopItem::FreeStickers)

    user.ledger_entries.create!(
      amount: total_cost,
      reason: "Refund for rejected order of #{shop_item.name.pluralize(quantity)}",
      created_by: "System",
      ledgerable: self
    )
  end

  def fraud_related_project_exists
    unless Project.exists?(fraud_related_project_id)
      errors.add(:fraud_related_project_id, "project ##{fraud_related_project_id} does not exist")
    end
  end

  def set_region_from_address
    return if region.present?
    return unless frozen_address.present? && frozen_address["country"].present?

    self.region = Shop::Regionalizable.country_to_region(frozen_address["country"])
  end

  def assign_default_user
    return if assigned_to_user_id.present?

    assignee_id = shop_item&.default_assignee_for_region(region)
    return unless assignee_id.present?

    update(assigned_to_user_id: assignee_id)
  end

  def notify_amber_if_verification_call_required
    return unless shop_item.requires_verification_call?

    SendSlackDmJob.perform_later(
      "U054VC2KM9P",
      nil,
      blocks_path: "notifications/shop_orders/new_verification_call_order",
      locals: { order: self }
    )
  end

  def hold_if_usps_suspended
    return unless frozen_address.present?

    address_country = frozen_address["country"]
    return unless address_country.present?
    return if USPS_SUSPENSION_EXEMPT_TYPES.include?(shop_item.type)
    return unless USPS_SUSPENDED_COUNTRIES.include?(address_country.upcase)

    place_on_hold! if may_place_on_hold?
  end

  def notify_assigned_user
    return unless assigned_to_user_id.present?

    user = assigned_to_user
    return unless user&.slack_id.present?

    Rails.logger.info "[ShopOrder] Sending assignment notification to #{user.display_name} (#{user.slack_id})"

    SendSlackDmJob.perform_later(
      user.slack_id,
      nil,
      blocks_path: "notifications/shop_orders/assigned",
      locals: { order: self, admin_url: Rails.application.routes.url_helpers.admin_shop_order_url(self, host: "stardance.hackclub.com", protocol: "https") }
    )
  end
end
