require "test_helper"

# The subject's stardust ledger, loaded into the fraud page on demand behind
# the balance's own toggle.
class Admin::Fraud::SubjectBalancesTest < ActionDispatch::IntegrationTest
  include UserFactory

  setup do
    @squad = create_user(slack_id: "U_FRAUD_BALANCE_SQUAD", display_name: "balancesquaddie")
    @squad.grant_role!(:fraud_fraud_squad_squad)

    @subject = create_user(slack_id: "U_FRAUD_BALANCE_SUBJECT", display_name: "balancesubject")
  end

  test "the panel lists the subject's ledger entries newest first" do
    older = credit(50, "Older payout", at: 2.days.ago)
    newer = credit(-20, "Shop order", at: 1.hour.ago)

    sign_in @squad
    get admin_fraud_subject_balance_path(@subject)

    assert_response :success
    assert_select "turbo-frame#fraud-subject-balance"
    assert_select ".fraud-subject__balance-table tbody tr", 2
    assert_select ".fraud-subject__balance-table tbody tr:first-child", /#{newer.reason}/
    assert_select ".fraud-subject__balance-table tbody tr:last-child", /#{older.reason}/
    assert_select ".fraud-subject__balance-amount--negative", /-20/
  end

  test "a subject with no ledger entries says so" do
    sign_in @squad
    get admin_fraud_subject_balance_path(@subject)

    assert_response :success
    assert_select ".fraud-subject__balance-empty"
  end

  test "the subject page offers the toggle that loads the panel" do
    sign_in @squad
    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_select "details.fraud-subject__balance-history summary", text: "Balance history"
    assert_select "turbo-frame#fraud-subject-balance[src=?][loading=?]",
                  admin_fraud_subject_balance_path(@subject), "lazy"
  end

  test "someone outside the fraud dept cannot read the ledger" do
    outsider = create_user(slack_id: "U_FRAUD_BALANCE_OUTSIDER", display_name: "outsider")

    sign_in outsider
    get admin_fraud_subject_balance_path(@subject)

    assert_response :not_found
  end

  private

  def credit(amount, reason, at: Time.current)
    entry = @subject.ledger_entries.create!(amount: amount, reason: reason, ledgerable: @subject, created_by: "test")
    entry.update_columns(created_at: at)
    entry
  end
end
