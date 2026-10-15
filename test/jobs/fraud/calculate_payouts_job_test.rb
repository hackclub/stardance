require "test_helper"

class Fraud::CalculatePayoutsJobTest < ActiveJob::TestCase
  setup do
    @reviewer1 = create_user(slack_id: "UREVIEWER1", display_name: "fraudreviewer1")
    @reviewer2 = create_user(slack_id: "UREVIEWER2", display_name: "fraudreviewer2")
    @subject = create_user(slack_id: "UFRAUDSUBJECT", display_name: "fraudsubject")
  end

  test "a completed per-person review payout is credited in its own line" do
    payout = complete_payout(@reviewer1, flag_count: 1, order_count: 1, integrity_count: 1, amount: 4.81)

    assert_difference -> { @reviewer1.ledger_entries.count }, 1 do
      Fraud::CalculatePayoutsJob.perform_now
    end

    line = payout.reload.fraud_payout_line
    assert_not_nil line, "the payout is swept into the run"
    assert_equal 5, line.amount, "4.81 rounds to a whole number at credit time"
    assert_match "1 person fully reviewed", line.ledger_entries.sole.reason
  end

  test "records the totals of everything it swept" do
    complete_payout(@reviewer1, flag_count: 2, order_count: 1, integrity_count: 0, amount: 3.4)
    complete_payout(@reviewer2, flag_count: 1, order_count: 0, integrity_count: 1, amount: 2.5)

    Fraud::CalculatePayoutsJob.perform_now

    run = FraudPayoutRun.sole
    assert_equal "approved", run.aasm_state
    assert_equal 5, run.total_orders, "three items for one reviewer, two for the other"
    assert_equal 6, run.total_amount, "3.4 and 2.5 each round at credit time"
  end

  test "a reviewer's payouts are collapsed into a single line" do
    complete_payout(@reviewer1, flag_count: 1, order_count: 0, integrity_count: 0, amount: 1.1)
    complete_payout(@reviewer1, flag_count: 0, order_count: 2, integrity_count: 0, amount: 2.2)

    Fraud::CalculatePayoutsJob.perform_now

    line = FraudPayoutRun.sole.lines.sole
    assert_equal @reviewer1.id, line.user_id
    assert_equal 3, line.order_count
    assert_equal 3, line.amount
  end

  test "a run records who triggered it" do
    trigger = create_user(slack_id: "UREVIEWER_TRIGGER", display_name: "fraudtrigger")
    complete_payout(@reviewer1, flag_count: 1, order_count: 0, integrity_count: 0, amount: 1.1)

    Fraud::CalculatePayoutsJob.perform_now(triggered_by: trigger)

    run = FraudPayoutRun.sole

    assert_equal trigger, run.approved_by_user
    assert_not_nil run.approved_at
    assert_equal trigger.id.to_s,
                 PaperTrail::Version.find_by(item_type: "FraudPayoutRun", item_id: run.id,
                                             event: "approved").whodunnit
  end

  test "a run nobody triggered has no approver to record" do
    complete_payout(@reviewer1, flag_count: 1, order_count: 0, integrity_count: 0, amount: 1.1)

    Fraud::CalculatePayoutsJob.perform_now

    assert_nil FraudPayoutRun.sole.approved_by_user
  end

  test "pays every completed review payout, however old" do
    old = complete_payout(@reviewer1, flag_count: 2, order_count: 0, integrity_count: 0, amount: 1.2,
                          completed_at: 90.days.ago)
    old.update_columns(created_at: 90.days.ago)

    assert_difference -> { @reviewer1.ledger_entries.count }, 1 do
      Fraud::CalculatePayoutsJob.perform_now
    end

    assert_not_nil old.reload.fraud_payout_line_id
    assert_empty FraudReviewPayout.payable
  end

  test "a review payout that is not complete is left for a later run" do
    FraudReviewPayout.create!(reviewer: @reviewer1, subject: @subject, flag_count: 1,
                              order_count: 0, integrity_count: 0, amount: 1.1)

    Fraud::CalculatePayoutsJob.perform_now

    assert_equal 0, FraudPayoutRun.count
    assert_nil FraudReviewPayout.sole.fraud_payout_line_id
  end

  test "a payout a previous run already swept is not paid twice" do
    complete_payout(@reviewer1, flag_count: 1, order_count: 0, integrity_count: 0, amount: 1.1)
    Fraud::CalculatePayoutsJob.perform_now

    complete_payout(@reviewer2, flag_count: 3, order_count: 0, integrity_count: 0, amount: 1.3)
    Fraud::CalculatePayoutsJob.perform_now

    assert_equal 2, FraudPayoutRun.count
    second_run = FraudPayoutRun.order(:created_at).last
    assert_equal 3, second_run.total_orders
    assert_equal [ @reviewer2.id ], second_run.lines.pluck(:user_id)
  end

  test "rejecting a run releases its payouts for the next one" do
    payout = complete_payout(@reviewer1, flag_count: 1, order_count: 0, integrity_count: 0, amount: 1.1)
    Fraud::CalculatePayoutsJob.perform_now

    run = FraudPayoutRun.sole
    run.update_columns(aasm_state: "pending_approval")
    run.reject!

    assert_nil payout.reload.fraud_payout_line_id
    assert_includes FraudReviewPayout.payable, payout
  end

  test "does nothing when nothing is payable" do
    Fraud::CalculatePayoutsJob.perform_now

    assert_equal 0, FraudPayoutRun.count
  end

  private

  def complete_payout(reviewer, flag_count:, order_count:, integrity_count:, amount:, completed_at: Time.current)
    FraudReviewPayout.create!(
      reviewer: reviewer,
      subject: @subject,
      flag_count: flag_count,
      order_count: order_count,
      integrity_count: integrity_count,
      amount: amount,
      completed_at: completed_at
    )
  end
end
