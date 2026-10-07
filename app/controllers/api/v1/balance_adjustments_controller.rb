class Api::V1::BalanceAdjustmentsController < Api::V1::AdminApiController
  def create
    user = User.find(params[:user_id])
    return render json: { error: "Forbidden" }, status: :forbidden unless ::Admin::UserPolicy.new(current_api_user, user).adjust_balance?

    amount = Integer(params[:amount], exception: false)
    reason = params[:reason].presence

    return render json: { error: "amount must be a non-zero integer" }, status: :unprocessable_entity if amount.nil? || amount.zero?
    return render json: { error: "reason is required" }, status: :unprocessable_entity if reason.blank?

    entry = user.ledger_entries.create!(
      amount: amount,
      reason: reason,
      created_by: "#{current_api_user.display_name} (#{current_api_user.id}) via API",
      ledgerable: user
    )

    render json: { id: entry.id, user_id: user.id, amount: entry.amount, reason: entry.reason }, status: :created
  end
end
