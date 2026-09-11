require "test_helper"

class Fraud::CalculatePayoutsJobTest < ActiveJob::TestCase
  setup do
    @reviewer1 = create_user(slack_id: "UREVIEWER1", display_name: "fraudreviewer1")
    @reviewer2 = create_user(slack_id: "UREVIEWER2", display_name: "fraudreviewer2")
    @buyer = create_user(slack_id: "UFRAUDBUYER", display_name: "fraudbuyer")
    @buyer.update!(has_gotten_free_stickers: true) # clears the shop-tutorial gate

    @item = ShopItem.new(
      name: "Test Item",
      description: "A test item reviewers' orders are attached to",
      ticket_cost: 0,
      type: "ShopItem::ThirdPartyPhysical",
      enabled: true
    )
    @item.image.attach(
      io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")),
      filename: "px.png",
      content_type: "image/png"
    )
    @item.save!

    @order1 = create_order(@buyer, @item)
    @order2 = create_order(@buyer, @item)
    @order3 = create_order(@buyer, @item)

    review!(@order1, @reviewer1, "rejected")
    review!(@order2, @reviewer1, "awaiting_periodical_fulfillment")
    review!(@order3, @reviewer2, "on_hold")
  end

  test "a completed per-person review payout is credited in its own line" do
    clearer = create_user(slack_id: "UREVIEWER3", display_name: "fraudreviewer3")
    payout = FraudReviewPayout.create!(reviewer: clearer, subject: @buyer, flag_count: 1,
                                       order_count: 1, integrity_count: 1, amount: 4.81,
                                       completed_at: Time.current)

    assert_difference -> { clearer.ledger_entries.count }, 1 do
      Fraud::CalculatePayoutsJob.perform_now
    end

    line = payout.reload.fraud_payout_line
    assert_not_nil line, "the payout is swept into the run"
    assert_equal 5, line.amount, "4.81 rounds to a whole number at credit time"
    assert_match "1 person fully reviewed", line.ledger_entries.sole.reason
  end

  test "a manual run records who triggered it" do
    trigger = create_user(slack_id: "UREVIEWER_TRIGGER", display_name: "fraudtrigger")

    Fraud::CalculatePayoutsJob.perform_now(manual: true, triggered_by: trigger)

    run = FraudPayoutRun.sole

    assert_equal trigger, run.approved_by_user
    assert_not_nil run.approved_at
    assert_equal trigger.id.to_s,
                 PaperTrail::Version.find_by(item_type: "FraudPayoutRun", item_id: run.id,
                                             event: "approved").whodunnit
  end

  test "a scheduled run has no approver to record" do
    Fraud::CalculatePayoutsJob.perform_now

    assert_nil FraudPayoutRun.sole.approved_by_user
  end

  test "a manual run pays every completed review payout, however old" do
    clearer = create_user(slack_id: "UREVIEWER_OLD", display_name: "fraudreviewerold")
    old = FraudReviewPayout.create!(reviewer: clearer, subject: @buyer, flag_count: 2,
                                    order_count: 0, integrity_count: 0, amount: 1.2,
                                    completed_at: 90.days.ago)
    old.update_columns(created_at: 90.days.ago)

    assert_difference -> { clearer.ledger_entries.count }, 1 do
      Fraud::CalculatePayoutsJob.perform_now(manual: true)
    end

    assert_not_nil old.reload.fraud_payout_line_id
    assert_empty FraudReviewPayout.payable
  end

  test "a review payout that is not complete is left for a later run" do
    FraudReviewPayout.create!(reviewer: @reviewer1, subject: @buyer, flag_count: 1,
                              order_count: 0, integrity_count: 0, amount: 1.1)

    Fraud::CalculatePayoutsJob.perform_now

    assert_nil FraudReviewPayout.sole.fraud_payout_line_id
  end

  test "creates a payout run with totals from the bracket calculator" do
    Fraud::CalculatePayoutsJob.perform_now

    run = FraudPayoutRun.last
    assert_equal "approved", run.aasm_state
    assert_equal 3, run.total_orders
    # reviewer1 reviewed 2/2 (the leader, 100% bracket -> full $1000)
    # reviewer2 reviewed 1/2 (50% of the leader -> 45-59% bracket -> $550)
    assert_equal 1550, run.total_amount
  end

  test "pays reviewers relative to the leader, not a fixed rate per order" do
    Fraud::CalculatePayoutsJob.perform_now

    run = FraudPayoutRun.last
    line1 = run.lines.find_by(user: @reviewer1)
    line2 = run.lines.find_by(user: @reviewer2)

    assert_equal 2, line1.order_count
    assert_equal 1000, line1.amount

    assert_equal 1, line2.order_count
    assert_equal 550, line2.amount
  end

  test "associates orders with their reviewer's payout line" do
    Fraud::CalculatePayoutsJob.perform_now

    run = FraudPayoutRun.last
    line1 = run.lines.find_by(user: @reviewer1)
    line2 = run.lines.find_by(user: @reviewer2)

    assert_equal line1.id, @order1.reload.fraud_payout_line_id
    assert_equal line1.id, @order2.reload.fraud_payout_line_id
    assert_equal line2.id, @order3.reload.fraud_payout_line_id
  end

  test "credits the first reviewer to touch an order, not whoever left it in its final state" do
    order = create_order(@buyer, @item)
    review!(order, @reviewer2, "on_hold")
    review!(order, @reviewer1, "rejected")

    Fraud::CalculatePayoutsJob.perform_now

    run = FraudPayoutRun.last
    assert_equal run.lines.find_by(user: @reviewer2).id, order.reload.fraud_payout_line_id
  end

  test "approving the run pays out reviewers via ledger entries" do
    Fraud::CalculatePayoutsJob.perform_now

    run = FraudPayoutRun.last
    line1 = run.lines.find_by(user: @reviewer1)

    entry = @reviewer1.ledger_entries.find_by(ledgerable: line1)
    assert_not_nil entry
    assert_equal 1000, entry.amount
  end

  test "skips orders already paid out by a previous run" do
    Fraud::CalculatePayoutsJob.perform_now
    assert_equal 1, FraudPayoutRun.count

    order4 = create_order(@buyer, @item)
    review!(order4, @reviewer1, "rejected")
    Fraud::CalculatePayoutsJob.perform_now

    assert_equal 2, FraudPayoutRun.count
    second_run = FraudPayoutRun.order(:created_at).last
    assert_equal 1, second_run.total_orders
  end

  test "manual run only includes orders created since the last run" do
    Fraud::CalculatePayoutsJob.perform_now

    new_order = travel_to(1.hour.from_now) { create_order(@buyer, @item) }
    review!(new_order, @reviewer1, "rejected")

    old_order = travel_to(1.week.ago) { create_order(@buyer, @item) }
    review!(old_order, @reviewer2, "rejected")

    Fraud::CalculatePayoutsJob.perform_now(manual: true)

    second_run = FraudPayoutRun.order(:created_at).last
    assert_equal 1, second_run.total_orders
    assert_not_nil new_order.reload.fraud_payout_line_id
    assert_nil old_order.reload.fraud_payout_line_id
  end

  test "counts an order toward total_orders even when its reviewer can't be attributed" do
    system_order = create_order(@buyer, @item)
    system_order.update!(
      aasm_state: "rejected", # no PaperTrail.request whodunnit set
      internal_rejection_reason: "flagged as fraud",
      fraud_related_project_id: projects(:one).id
    )

    Fraud::CalculatePayoutsJob.perform_now

    run = FraudPayoutRun.last
    assert_equal 4, run.total_orders
    assert_nil system_order.reload.fraud_payout_line_id
  end

  test "does nothing when no eligible orders" do
    ShopOrder.update_all(aasm_state: "pending")

    Fraud::CalculatePayoutsJob.perform_now

    assert_equal 0, FraudPayoutRun.count
  end

  private

  def create_order(buyer, item)
    ShopOrder.create!(
      user: buyer,
      shop_item: item,
      quantity: 1,
      frozen_item_price: 0,
      frozen_address: { "country" => "US" }.to_json,
      aasm_state: "pending"
    )
  end

  def review!(order, reviewer, state)
    attrs = { aasm_state: state }
    if state == "rejected"
      attrs[:internal_rejection_reason] = "flagged as fraud"
      attrs[:fraud_related_project_id] = projects(:one).id
    end

    PaperTrail.request(whodunnit: reviewer.id) do
      order.update!(attrs)
    end
  end
end
