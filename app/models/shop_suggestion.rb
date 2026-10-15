# == Schema Information
#
# Table name: shop_suggestions
#
#  id               :bigint           not null, primary key
#  aasm_state       :string           default("pending"), not null
#  description      :text
#  discarded_at     :datetime
#  name             :text
#  rejection_reason :string
#  url              :string
#  usd_cost         :decimal(8, 2)
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  shop_item_id     :bigint
#  user_id          :bigint           not null
#
# Indexes
#
#  index_shop_suggestions_on_aasm_state    (aasm_state)
#  index_shop_suggestions_on_shop_item_id  (shop_item_id)
#  index_shop_suggestions_on_user_id       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class ShopSuggestion < ApplicationRecord
  include AASM
  include Ledgerable

  has_paper_trail

  belongs_to :user
  belongs_to :shop_item, optional: true
  has_one_attached :image
  has_many :shop_suggestion_votes, dependent: :destroy

  scope :kept, -> { where(discarded_at: nil) }

  SUBMISSION_COST = 10

  validates :name, presence: true, length: { minimum: 3, maximum: 200 }
  validates :description, presence: true, length: { minimum: 10, maximum: 5000 }
  validates :url, allow_blank: true, length: { maximum: 2000 }, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :usd_cost, presence: true, numericality: { greater_than: 0, less_than: 1_000_000 }
  validate :sufficient_balance, on: :create
  validate :image_present, on: :create

  aasm column: :aasm_state do
    state :pending, initial: true
    state :accepted
    state :rejected

    event :accept do
      transitions from: :pending, to: :accepted
      after :refund_submission_fee
    end

    event :reject do
      transitions from: :pending, to: :rejected
    end
  end

  after_create :charge_submission_fee

  def vote_count = shop_suggestion_votes.size
  def discarded? = discarded_at.present?

  def discard!
    update!(discarded_at: Time.current)
  end

  private

  def charge_submission_fee
    LedgerEntry.create!(user: user, ledgerable: self, amount: -SUBMISSION_COST, reason: "Shop suggestion submission")
  end

  def refund_submission_fee
    LedgerEntry.create!(user: user, ledgerable: self, amount: SUBMISSION_COST, reason: "Shop suggestion accepted")
  end

  def sufficient_balance
    return unless user
    return if user.balance >= SUBMISSION_COST

    errors.add(:base, "You need at least #{SUBMISSION_COST} Stardust to submit a suggestion (you have #{user.balance})")
  end

  def image_present
    errors.add(:image, "must be attached") unless image.attached?
  end
end
