require "test_helper"

class Admin::Users::BalanceAdjustmentsControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  setup do
    @admin = create_user(slack_id: "U_BALANCE_ADMIN", display_name: "balanceadmin")
    @admin.grant_role!(:admin)
    @subject = create_user(slack_id: "U_BALANCE_SUBJECT", display_name: "balancesubject")
  end

  test "an adjustment records a ledger entry and returns to the page it came from" do
    sign_in @admin

    assert_difference -> { @subject.ledger_entries.count }, 1 do
      post admin_user_balance_adjustments_path(@subject),
           params: { amount: 25, reason: "Refund" },
           headers: { "HTTP_REFERER" => admin_fraud_subject_url(@subject) }
    end

    assert_redirected_to admin_fraud_subject_url(@subject)
    assert_equal 25, @subject.balance
  end

  test "an adjustment with no referrer returns to the admin user page" do
    sign_in @admin

    post admin_user_balance_adjustments_path(@subject), params: { amount: 25, reason: "Refund" }

    assert_redirected_to admin_user_path(@subject)
  end

  test "a rejected adjustment also returns to the page it came from" do
    sign_in @admin

    assert_no_difference -> { @subject.ledger_entries.count } do
      post admin_user_balance_adjustments_path(@subject),
           params: { amount: 0, reason: "Nothing" },
           headers: { "HTTP_REFERER" => admin_fraud_subject_url(@subject) }
    end

    assert_redirected_to admin_fraud_subject_url(@subject)
  end
end
