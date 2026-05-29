class Admin::Users::BalanceAdjustmentsController < Admin::ApplicationController
  def create
    @user = User.find(params[:user_id])
    authorize @user, :adjust_balance?

    amount = params[:amount].to_i
    reason = params[:reason].presence

    if fraud_dept_stardust_limit_exceeded?(amount)
      flash[:alert] = "Fraud department members can only grant up to 1 Stardust without the grant_stardust permission."
      return redirect_to admin_user_path(@user)
    end

    if amount.zero?
      flash[:alert] = "Amount cannot be zero."
      return redirect_to admin_user_path(@user)
    end

    if reason.blank?
      flash[:alert] = "Reason is required."
      return redirect_to admin_user_path(@user)
    end

    @user.ledger_entries.create!(
      amount: amount,
      reason: reason,
      created_by: "#{current_user.display_name} (#{current_user.id})",
      ledgerable: @user
    )

    flash[:notice] = "Balance adjusted by #{amount} for #{@user.display_name}."
    redirect_to admin_user_path(@user)
  end

  private

  def fraud_dept_stardust_limit_exceeded?(amount)
    return false unless current_user.has_role?(:fraud_dept)
    return false if current_user.has_role?(:admin) || current_user.has_role?(:super_admin)
    return false if Flipper.enabled?(:grant_stardust, current_user)

    amount > 1
  end
end
