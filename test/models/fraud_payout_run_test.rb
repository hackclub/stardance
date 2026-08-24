require "test_helper"

# == Schema Information
#
# Table name: fraud_payout_runs
#
#  id                  :bigint           not null, primary key
#  aasm_state          :string
#  approved_at         :datetime
#  period_end          :datetime
#  period_start        :datetime
#  total_amount        :integer
#  total_orders        :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  approved_by_user_id :bigint
#
class FraudPayoutRunTest < ActiveSupport::TestCase
  def create_review_version(whodunnit:, to_state:)
    ::PaperTrail::Version.create!(
      item_type: "ShopOrder",
      item_id: SecureRandom.random_number(1_000_000).to_s,
      event: "update",
      whodunnit: whodunnit,
      object_changes: { aasm_state: [ "awaiting_verification", to_state ] }
    )
  end

  test "reviewer_versions only includes ShopOrder aasm_state changes with a whodunnit" do
    review = create_review_version(whodunnit: "1", to_state: "rejected")
    create_review_version(whodunnit: nil, to_state: "rejected")
    ::PaperTrail::Version.create!(item_type: "ShopOrder", item_id: "999", event: "update", whodunnit: "1", object_changes: { tracking_number: [ nil, "abc" ] }.to_json)

    assert_equal [ review.id ], FraudPayoutRun.reviewer_versions.pluck(:id)
  end

  test "reviewer_from_version returns the whodunnit as an integer for review-state transitions" do
    version = create_review_version(whodunnit: "42", to_state: "on_hold")
    assert_equal 42, FraudPayoutRun.reviewer_from_version(version)
  end

  test "reviewer_from_version returns nil for non-review-state transitions" do
    version = create_review_version(whodunnit: "42", to_state: "fulfilled")
    assert_nil FraudPayoutRun.reviewer_from_version(version)
  end
end
