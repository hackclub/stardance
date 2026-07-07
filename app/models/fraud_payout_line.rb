# frozen_string_literal: true

# == Schema Information
#
# Table name: fraud_payout_lines
#
#  id                  :bigint           not null, primary key
#  amount              :integer
#  order_count         :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  fraud_payout_run_id :bigint           not null
#  user_id             :bigint           not null
#
# Indexes
#
#  index_fraud_payout_lines_on_fraud_payout_run_id  (fraud_payout_run_id)
#  index_fraud_payout_lines_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (fraud_payout_run_id => fraud_payout_runs.id)
#  fk_rails_...  (user_id => users.id)
#
class FraudPayoutLine < ApplicationRecord
  include Ledgerable

  belongs_to :fraud_payout_run
  belongs_to :user

  has_many :shop_orders, dependent: :nullify
end
