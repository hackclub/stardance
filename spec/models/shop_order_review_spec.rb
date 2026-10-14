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
require 'rails_helper'

RSpec.describe ShopOrderReview, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
