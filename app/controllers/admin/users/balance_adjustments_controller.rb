class Admin::Users::BalanceAdjustmentsController < Admin::ApplicationController
  def create
    @user = User.find(params[:user_id])
    authorize @user, :adjust_balance?

    amount = params[:amount].to_i
    reason = params[:reason].presence

    if fraud_dept_stardust_limit_exceeded?(amount)
      flash[:alert] = "Fraud department members can only grant up to 1 Stardust without the grant_stardust permission."
      return redirect_back_to_origin
    end

    if amount.zero?
      flash[:alert] = "Amount cannot be zero."
      return redirect_back_to_origin
    end

    if reason.blank?
      flash[:alert] = "Reason is required."
      return redirect_back_to_origin
    end

    @user.ledger_entries.create!(
      amount: amount,
      reason: reason,
      created_by: "#{current_user.display_name} (#{current_user.id})",
      ledgerable: @user
    )

    flash[:notice] = "Balance adjusted by #{amount} for #{@user.display_name}."
    redirect_back_to_origin
  end

  private

  # Adjustments come from both the admin user page and the fraud subject page,
  # so the reviewer lands back on whichever one they submitted from.
  def redirect_back_to_origin
    redirect_back_or_to admin_user_path(@user)
  end

  def fraud_dept_stardust_limit_exceeded?(amount)
    return false unless current_user.has_role?(:fraud_dept)
    return false if current_user.has_role?(:admin) || current_user.has_role?(:super_admin)
    return false if Flipper.enabled?(:grant_stardust, current_user)

    amount > 1
  end
end
