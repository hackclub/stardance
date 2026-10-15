# == Schema Information
#
# Table name: shop_order_reviews
#
#  id                     :bigint           not null, primary key
#  reason                 :text             not null
#  verdict                :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  fraud_review_payout_id :bigint
#  shop_order_id          :bigint           not null
#  user_id                :bigint           not null
#
# Indexes
#
#  index_shop_order_reviews_on_fraud_review_payout_id     (fraud_review_payout_id)
#  index_shop_order_reviews_on_shop_order_id              (shop_order_id)
#  index_shop_order_reviews_on_shop_order_id_and_user_id  (shop_order_id,user_id) UNIQUE
#  index_shop_order_reviews_on_user_id                    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (fraud_review_payout_id => fraud_review_payouts.id)
#  fk_rails_...  (shop_order_id => shop_orders.id)
#  fk_rails_...  (user_id => users.id)
#
class ShopOrderReview < ApplicationRecord
  has_paper_trail

  belongs_to :shop_order
  belongs_to :user
  belongs_to :fraud_review_payout, optional: true, inverse_of: :shop_order_reviews

  APPROVE = "approve"
  REJECT = "reject"
  VERDICTS = [ APPROVE, REJECT ].freeze

  # How many reviewers have to reach the same verdict before a high-value order
  # can move on that verdict.
  REQUIRED_COUNT = 2

  validates :user_id, uniqueness: { scope: :shop_order_id, message: "has already reviewed this order" }
  validates :verdict, presence: true, inclusion: { in: VERDICTS }
  validates :reason, presence: true

  # The ids of orders this reviewer has already reviewed that still wait on
  # someone else, for use as a subquery. Counted per verdict: a split decision
  # settles nothing, so the order is still waiting.
  scope :awaiting_another_reviewer, ->(reviewer) {
    group(:shop_order_id)
      .having("COUNT(*) FILTER (WHERE verdict = ?) < ?", APPROVE, REQUIRED_COUNT)
      .having("COUNT(*) FILTER (WHERE verdict = ?) < ?", REJECT, REQUIRED_COUNT)
      .having("BOOL_OR(shop_order_reviews.user_id = ?)", reviewer.id)
      .select(:shop_order_id)
  }
end
