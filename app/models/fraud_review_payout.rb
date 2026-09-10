# What a reviewer earned for clearing every open review on one person.
#
# The unit is the person, not the item: the payout lands once nothing is left
# waiting on them, and the multipliers say how much work that person was. The
# items are claimed by the payout so neither this nor FraudPayoutRun can pay
# for the same review twice.
# == Schema Information
#
# Table name: fraud_review_payouts
#
#  id                   :bigint           not null, primary key
#  amount               :decimal(10, 2)   default(0.0), not null
#  completed_at         :datetime
#  flag_count           :integer          default(0), not null
#  integrity_count      :integer          default(0), not null
#  order_count          :integer          default(0), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  fraud_payout_line_id :bigint
#  reviewer_id          :bigint           not null
#  subject_id           :bigint           not null
#
# Indexes
#
#  index_fraud_review_payouts_on_fraud_payout_line_id  (fraud_payout_line_id)
#  index_fraud_review_payouts_on_reviewer_id           (reviewer_id)
#  index_fraud_review_payouts_on_subject_id            (subject_id)
#
# Foreign Keys
#
#  fk_rails_...  (fraud_payout_line_id => fraud_payout_lines.id)
#  fk_rails_...  (reviewer_id => users.id)
#  fk_rails_...  (subject_id => users.id)
#
class FraudReviewPayout < ApplicationRecord
  include Ledgerable

  has_paper_trail

  BASE_AMOUNT = 1.0
  FLAG_WEIGHT = 0.1

  # A big-ticket order is the one worth getting right, so it carries more than
  # a sticker does. Deliberately its own line rather than ShopOrder's
  # HIGH_VALUE_THRESHOLD: that one sits at 2000 and gates dual review and
  # auto-approval, so moving it to price a payout would change what the shop
  # actually does with an order.
  HIGH_VALUE_ORDER_STARDUST = 500
  HIGH_VALUE_ORDER_WEIGHT = 1.25
  ORDER_WEIGHT = 0.75

  # An integrity check is worth what the ship under it is worth: banding by
  # hours means a 200 hour project is not paid the same as an afternoon.
  # Read as "under this many hours, this weight"; anything above the last band
  # takes LONGEST_PROJECT_WEIGHT.
  PROJECT_WEIGHT_BANDS = [ [ 5, 0.25 ], [ 10, 0.5 ], [ 25, 0.75 ], [ 100, 1.0 ] ].freeze
  LONGEST_PROJECT_WEIGHT = 1.5

  belongs_to :reviewer, class_name: "User"
  belongs_to :subject, class_name: "User"
  belongs_to :fraud_payout_line, optional: true

  has_many :project_reports, class_name: "Project::Report", foreign_key: :fraud_review_payout_id,
           inverse_of: :fraud_review_payout, dependent: :nullify
  has_many :shop_orders, foreign_key: :fraud_review_payout_id,
           inverse_of: :fraud_review_payout, dependent: :nullify
  has_many :certification_integrities, class_name: "Certification::Integrity",
           foreign_key: :fraud_review_payout_id, inverse_of: :fraud_review_payout, dependent: :nullify

  validates :flag_count, :order_count, :integrity_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :amount, numericality: { greater_than: 0 }

  scope :unpaid, -> { where(fraud_payout_line_id: nil) }
  scope :payable, -> { unpaid.where.not(completed_at: nil) }

  KIND_COUNTERS = {
    "Project::Report" => :flag_count,
    "ShopOrder" => :order_count,
    "Certification::Integrity" => :integrity_count
  }.freeze

  # Claims one settled item onto the reviewer's running tally for this person,
  # creating the tally on their first verdict. Claiming as the verdict lands is
  # what keeps the counts to the work actually done here, rather than sweeping
  # up every item the person has ever had settled.
  def self.claim!(record, reviewer:, subject:)
    counter = KIND_COUNTERS[record.class.name]
    return if counter.nil? || record.fraud_review_payout_id.present?

    transaction do
      payout = open_for(reviewer: reviewer, subject: subject)
      record.update_column(:fraud_review_payout_id, payout.id)
      payout.increment(counter)
      payout.recalculate_amount
      payout.save!
      payout
    end
  end

  def self.open_for(reviewer:, subject:)
    unpaid.where(reviewer: reviewer, subject: subject, completed_at: nil).first ||
      create!(reviewer: reviewer, subject: subject, amount: BASE_AMOUNT)
  end

  # Nothing left waiting on the person, so the tally is final and payable.
  def complete!
    update!(completed_at: Time.current)
  end

  def self.amount_for(flag: 0, order: 0, integrity: 0)
    (BASE_AMOUNT * (1 + flag) * (1 + order) * (1 + integrity)).round(2)
  end

  def self.order_weight(order)
    value = [ order.total_cost_with_accessories.to_f, order.total_cost_with_modifiers.to_f ].max

    value > HIGH_VALUE_ORDER_STARDUST ? HIGH_VALUE_ORDER_WEIGHT : ORDER_WEIGHT
  end

  def self.integrity_weight(check)
    hours = check.ship_event&.hours_at_ship.to_f

    PROJECT_WEIGHT_BANDS.find { |ceiling, _| hours < ceiling }&.last || LONGEST_PROJECT_WEIGHT
  end

  # Weights come off the claimed records rather than a stored total, so an
  # order's value and a ship's hours are read from the things themselves and
  # cannot drift out of step with the counts.
  def weights
    {
      flag: (flag_count * FLAG_WEIGHT).round(4),
      order: shop_orders.sum { |order| self.class.order_weight(order) }.round(4),
      integrity: certification_integrities.sum { |check| self.class.integrity_weight(check) }.round(4)
    }
  end

  def recalculate_amount
    [ :shop_orders, :certification_integrities ].each { |name| association(name).reset }

    self.amount = self.class.amount_for(**weights)
  end

  # The whole-number amount a payout run credits. Kept off `amount` so the
  # exact figure stays on the record for anyone auditing the arithmetic.
  def credited_amount = amount.round

  def item_count = flag_count + order_count + integrity_count

  # Each source's own factor, so the readout shows the arithmetic rather than
  # only its result. All three are always present, sitting at 1 until that
  # source has something reviewed, so the line keeps its shape as it fills.
  def multipliers
    weights.transform_values { |weight| (1 + weight).round(2) }
  end
end
