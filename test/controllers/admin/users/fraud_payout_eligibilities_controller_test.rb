require "test_helper"

# Whether a reviewer's fraud work earns stardust is a payroll decision, so it
# sits with approving payout runs rather than with working the queue.
class Admin::Users::FraudPayoutEligibilitiesControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  setup do
    @admin = create_user(slack_id: "U_FPE_ADMIN", display_name: "fpe_admin")
    @admin.grant_role!(:admin)
    @reviewer = create_user(slack_id: "U_FPE_REVIEWER", display_name: "fpe_reviewer")
  end

  test "an admin turns a reviewer's payouts off and back on" do
    sign_in @admin

    patch admin_user_fraud_payout_eligibility_path(@reviewer), params: { disabled: "true" }

    assert_redirected_to admin_user_path(@reviewer)
    assert_predicate @reviewer.reload, :fraud_review_payouts_disabled?

    patch admin_user_fraud_payout_eligibility_path(@reviewer), params: { disabled: "false" }

    assert_not_predicate @reviewer.reload, :fraud_review_payouts_disabled?
  end

  test "the change is audit logged" do
    sign_in @admin

    patch admin_user_fraud_payout_eligibility_path(@reviewer), params: { disabled: "true" }

    # The model's own update version lands too, so the audit row is looked up by
    # the event rather than by taking the last one written.
    version = PaperTrail::Version.find_by(item_type: "User", item_id: @reviewer.id,
                                          event: "fraud_review_payouts_disabled")

    assert_not_nil version
    assert_equal @admin.id.to_s, version.whodunnit
  end

  test "a fraud reviewer cannot turn their own payouts off" do
    squad = create_user(slack_id: "U_FPE_SQUAD", display_name: "fpe_squad")
    squad.grant_role!(:fraud_fraud_squad_squad)
    sign_in squad

    patch admin_user_fraud_payout_eligibility_path(squad), params: { disabled: "true" }

    assert_not_predicate squad.reload, :fraud_review_payouts_disabled?
  end

  test "the control renders on the user page for an admin" do
    sign_in @admin

    get admin_user_path(@reviewer)

    assert_response :success
    assert_select "form[action=?]", admin_user_fraud_payout_eligibility_path(@reviewer)
  end
end
