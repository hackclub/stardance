require "test_helper"

class Api::V1::BalanceAdjustmentsControllerTest < ActionDispatch::IntegrationTest
  API_FLAG = :"public_api_2026-08-28"

  setup do
    @admin = User.create!(slack_id: "U_API_ADMIN", display_name: "api_admin", email: "api_admin@example.test", verification_status: "verified")
    @admin.grant_role!(:admin)
    @admin.regenerate_api_key
    @target = User.create!(slack_id: "U_API_TARGET", display_name: "scout", email: "scout@example.test", verification_status: "verified")
    Flipper.enable(API_FLAG, @admin)
  end

  teardown do
    Flipper.disable(API_FLAG, @admin)
  end

  test "creates a ledger entry for the user" do
    assert_difference -> { @target.ledger_entries.count }, 1 do
      post api_v1_user_balance_adjustments_path(@target), params: { amount: 25, reason: "Support Scout payout" }, headers: auth_headers
    end

    assert_response :created
    entry = @target.ledger_entries.order(:id).last
    assert_equal 25, entry.amount
    assert_equal "Support Scout payout", entry.reason
    assert_equal "api_admin (#{@admin.id}) via API", entry.created_by
  end

  test "rejects a zero or non-numeric amount" do
    post api_v1_user_balance_adjustments_path(@target), params: { amount: 0, reason: "x" }, headers: auth_headers
    assert_response :unprocessable_entity

    post api_v1_user_balance_adjustments_path(@target), params: { amount: "lots", reason: "x" }, headers: auth_headers
    assert_response :unprocessable_entity
  end

  test "requires a reason" do
    post api_v1_user_balance_adjustments_path(@target), params: { amount: 5 }, headers: auth_headers

    assert_response :unprocessable_entity
  end

  test "is forbidden for non-admins" do
    @target.regenerate_api_key
    Flipper.enable(API_FLAG, @target)

    post api_v1_user_balance_adjustments_path(@target), params: { amount: 5, reason: "x" }, headers: { "Authorization" => "Bearer #{@target.api_key}" }

    assert_response :forbidden
  ensure
    Flipper.disable(API_FLAG, @target)
  end

  test "returns not found for an unknown user" do
    post api_v1_user_balance_adjustments_path(user_id: 0), params: { amount: 5, reason: "x" }, headers: auth_headers

    assert_response :not_found
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@admin.api_key}" }
  end
end
