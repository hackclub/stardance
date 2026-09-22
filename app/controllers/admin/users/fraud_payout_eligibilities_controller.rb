class Admin::Users::FraudPayoutEligibilitiesController < Admin::ApplicationController
  def update
    @user = User.find(params[:user_id])
    authorize @user, :manage_fraud_review_payouts?

    was_disabled = @user.fraud_review_payouts_disabled_at
    now_disabled = params[:disabled] == "true" ? Time.current : nil
    @user.fraud_review_payouts_disabled_at = now_disabled

    if @user.save
      ::PaperTrail::Version.create!(
        item_type: "User",
        item_id: @user.id,
        event: "fraud_review_payouts_#{now_disabled ? 'disabled' : 'enabled'}",
        whodunnit: current_user.id.to_s,
        object_changes: { fraud_review_payouts_disabled_at: [ was_disabled, now_disabled ] }.to_json
      )

      flash[:notice] = "Fraud review payouts #{now_disabled ? 'disabled' : 're-enabled'} for #{@user.display_name}."
    else
      flash[:alert] = "Failed to update fraud review payouts."
    end

    redirect_to admin_user_path(@user)
  end
end
