require "test_helper"

# What a reviewer earns for clearing one person: a flat stardust per person,
# scaled by how much work that person turned out to be.

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
class FraudReviewPayoutTest < ActiveSupport::TestCase
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @reviewer = create_user(slack_id: "u-payout-reviewer", display_name: "payoutreviewer")
    @subject = create_user(slack_id: "u-payout-subject", display_name: "payoutsubject")
  end

  test "the three weights compound onto the base" do
    # 1 * (1 + 0.1) * (1 + 0.75) * (1 + 0.5)
    assert_equal 2.89, FraudReviewPayout.amount_for(flag: 0.1, order: 0.75, integrity: 0.5)
  end

  test "a person with nothing but the base pays one" do
    assert_equal 1.0, FraudReviewPayout.amount_for
  end

  test "an order over the payout threshold is worth more than an ordinary one" do
    ordinary = order_for_subject
    expensive = order_for_subject
    expensive.update_columns(frozen_item_price: FraudReviewPayout::HIGH_VALUE_ORDER_STARDUST + 1)

    assert_equal FraudReviewPayout::HIGH_VALUE_ORDER_WEIGHT, FraudReviewPayout.order_weight(expensive)
    assert_equal FraudReviewPayout::ORDER_WEIGHT, FraudReviewPayout.order_weight(ordinary)
  end

  test "the payout threshold is its own line, well under the shop's review one" do
    order = order_for_subject
    order.update_columns(frozen_item_price: 600)

    assert_not_predicate order, :high_value?, "the shop still treats 600 as ordinary"
    assert_equal FraudReviewPayout::HIGH_VALUE_ORDER_WEIGHT, FraudReviewPayout.order_weight(order)
  end

  test "an integrity check is weighted by the hours of the ship under it" do
    expected = { 1 => 0.25, 4.99 => 0.25, 5 => 0.5, 9.9 => 0.5, 10 => 0.75,
                 24.9 => 0.75, 25 => 1.0, 99.9 => 1.0, 100 => 1.5, 480 => 1.5 }

    expected.each do |hours, weight|
      check = pending_check_with_hours(hours)

      assert_equal weight, FraudReviewPayout.integrity_weight(check), "#{hours}h should weigh #{weight}"
    end
  end

  test "a ship with no recorded hours falls in the lowest band" do
    assert_equal 0.25, FraudReviewPayout.integrity_weight(pending_check_with_hours(nil))
  end

  test "claiming a review builds the tally and recomputes the amount" do
    report = flagged_report

    payout = FraudReviewPayout.claim!(report, reviewer: @reviewer, subject: @subject)

    assert_equal 1, payout.flag_count
    assert_equal 1.1, payout.amount.to_f
    assert_equal payout.id, report.reload.fraud_review_payout_id
  end

  test "the amount follows the weight of the items, not just how many" do
    cheap = FraudReviewPayout.claim!(order_for_subject, reviewer: @reviewer, subject: @subject)

    assert_equal 1.75, cheap.amount.to_f

    expensive = order_for_subject
    expensive.update_columns(frozen_item_price: FraudReviewPayout::HIGH_VALUE_ORDER_STARDUST + 1)
    payout = FraudReviewPayout.claim!(expensive, reviewer: @reviewer, subject: @subject)

    # 1 * (1 + 0.75 + 1.25)
    assert_equal 3.0, payout.amount.to_f
    assert_equal 2, payout.order_count
  end

  test "a second review lands on the same open tally" do
    first = FraudReviewPayout.claim!(flagged_report, reviewer: @reviewer, subject: @subject)
    second = FraudReviewPayout.claim!(flagged_report, reviewer: @reviewer, subject: @subject)

    assert_equal first.id, second.id
    assert_equal 2, second.flag_count
  end

  test "an already claimed review is never counted twice" do
    report = flagged_report
    payout = FraudReviewPayout.claim!(report, reviewer: @reviewer, subject: @subject)

    assert_nil FraudReviewPayout.claim!(report, reviewer: @reviewer, subject: @subject)
    assert_equal 1, payout.reload.flag_count
  end

  test "a reviewer with payouts turned off earns nothing new" do
    @reviewer.update!(fraud_review_payouts_disabled_at: Time.current)
    report = flagged_report

    assert_nil FraudReviewPayout.claim!(report, reviewer: @reviewer, subject: @subject)
    assert_nil report.reload.fraud_review_payout_id
    assert_empty FraudReviewPayout.where(reviewer: @reviewer)
  end

  test "stardust banked before payouts were turned off still pays out" do
    payout = FraudReviewPayout.claim!(flagged_report, reviewer: @reviewer, subject: @subject)
    payout.complete!
    @reviewer.update!(fraud_review_payouts_disabled_at: Time.current)

    assert_equal [ payout ], FraudReviewPayout.payable.to_a
  end

  test "a tally is only payable once the person is cleared" do
    payout = FraudReviewPayout.claim!(flagged_report, reviewer: @reviewer, subject: @subject)

    assert_empty FraudReviewPayout.payable
    payout.complete!
    assert_equal [ payout ], FraudReviewPayout.payable.to_a
  end

  test "the ledger is credited a whole number, the record keeps the exact one" do
    payout = FraudReviewPayout.claim!(flagged_report, reviewer: @reviewer, subject: @subject)
    FraudReviewPayout.claim!(order_for_subject, reviewer: @reviewer, subject: @subject)
    FraudReviewPayout.claim!(flagged_report, reviewer: @reviewer, subject: @subject)

    # 1 * (1 + 0.2) * (1 + 0.75) = 2.1
    assert_equal 2.1, payout.reload.amount.to_f
    assert_equal 2, payout.credited_amount
  end

  test "every source shows a factor, sitting at 1 until it has a review" do
    payout = FraudReviewPayout.claim!(flagged_report, reviewer: @reviewer, subject: @subject)
    FraudReviewPayout.claim!(order_for_subject, reviewer: @reviewer, subject: @subject)

    assert_equal({ flag: 1.1, order: 1.75, integrity: 1.0 }, payout.reload.multipliers)
  end

  test "a tally with nothing reviewed reads as all ones" do
    assert_equal({ flag: 1.0, order: 1.0, integrity: 1.0 }, FraudReviewPayout.new.multipliers)
  end

  test "an untouched source is 1, not 1.0" do
    # flag_count is an integer times a float, so it arrives as 1.0 where the
    # other two arrive as a bare 1. The readout has to even that out.
    payout = FraudReviewPayout.new

    assert_equal [ "1", "1", "1" ],
                 payout.multipliers.values.map { |f|
                   ActiveSupport::NumberHelper.number_to_rounded(f, precision: 2, strip_insignificant_zeros: true)
                 }
  end

  test "a person who comes back after being cleared starts a fresh tally" do
    first = FraudReviewPayout.claim!(flagged_report, reviewer: @reviewer, subject: @subject)
    FraudReviewPayout.claim!(flagged_report, reviewer: @reviewer, subject: @subject)
    first.complete!

    assert_equal [ 2, 1.2 ], [ first.reload.flag_count, first.amount.to_f ]

    second = FraudReviewPayout.claim!(flagged_report, reviewer: @reviewer, subject: @subject)

    assert_not_equal first.id, second.id, "the completed tally is closed, not reopened"
    assert_equal 1, second.flag_count, "the multiplier chain restarts from the base"
    assert_equal 1.1, second.amount.to_f
  end

  test "an order paid by a review payout is not paid again by a payout run" do
    order = order_for_subject
    order.update_columns(aasm_state: "rejected")

    assert_includes FraudPayoutRun.payout_eligible_orders, order

    FraudReviewPayout.claim!(order, reviewer: @reviewer, subject: @subject)

    assert_not_includes FraudPayoutRun.payout_eligible_orders, order
  end

  private

  def flagged_report
    project = Project.create!(title: "Flagged #{SecureRandom.hex(4)}")
    Project::Membership.create!(project:, user: @subject, role: :owner)
    Project::Report.create!(project:, reporter: @reviewer, reason: "fraud", status: :reviewed,
                            details: "Detailed fraud report body for the test suite.")
  end

  def pending_check_with_hours(hours)
    project = Project.create!(title: "Shipped #{SecureRandom.hex(4)}")
    Project::Membership.create!(project:, user: @subject, role: :owner)
    ship = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    # Creating the Post recalculates hours_at_ship off the devlogs in the ship
    # window, of which there are none here, so the figure is stamped after.
    Post.create!(project:, user: @subject, postable: ship)
    ship.update_columns(hours_at_ship: hours)
    Certification::Integrity.create!(ship_event: ship, status: :pending)
  end

  def order_for_subject
    item = ShopItem.new(name: "Payout patch #{SecureRandom.hex(4)}", description: "Test item",
                        ticket_cost: 0, usd_cost: 7, type: "ShopItem::ThirdPartyPhysical", enabled: true)
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!

    @subject.update!(has_gotten_free_stickers: true) # clears the shop-tutorial gate
    @subject.shop_orders.create!(shop_item: item, quantity: 1, frozen_address: { "country" => "US" })
  end
end
