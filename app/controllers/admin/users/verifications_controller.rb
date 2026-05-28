class Admin::Users::VerificationsController < Admin::ApplicationController
  def create
    @user = User.find(params[:user_id])
    authorize @user, :refresh_verification?

    identity = @user.identities.find_by(provider: "hack_club")

    unless identity&.access_token.present?
      flash[:alert] = "User has no Hack Club identity token."
      return redirect_to admin_user_path(@user)
    end

    payload = HCAService.identity(identity.access_token)
    if payload.blank?
      flash[:alert] = "Could not fetch verification status from HCA."
      return redirect_to admin_user_path(@user)
    end

    status = payload["verification_status"].to_s
    ysws_eligible = payload["ysws_eligible"] == true

    old_status = @user.verification_status
    old_ysws = @user.ysws_eligible
    @user.verification_status = status if User.verification_statuses.key?(status)
    @user.ysws_eligible = ysws_eligible
    @user.save!

    ::PaperTrail::Version.create!(
      item_type: "User",
      item_id: @user.id,
      event: "verification_refreshed",
      whodunnit: current_user.id.to_s,
      object_changes: {
        verification_status: [ old_status, @user.verification_status ],
        ysws_eligible: [ old_ysws, @user.ysws_eligible ]
      }.to_json
    )

    if @user.eligible_for_shop?
      Shop::ProcessVerifiedOrdersJob.perform_later(@user.id)
      flash[:notice] = "User is now verified (#{@user.verification_status}). Processing awaiting orders..."
    elsif @user.should_reject_orders?
      @user.reject_awaiting_verification_orders!
      flash[:notice] = "User verification failed (#{@user.verification_status}). Awaiting orders rejected."
    else
      flash[:notice] = "Verification status updated to: #{@user.verification_status}"
    end

    redirect_to admin_user_path(@user)
  rescue StandardError => e
    Rails.logger.error "Failed to refresh verification status for user #{@user.id}: #{e.message}"
    flash[:alert] = "Error refreshing verification: #{e.message}"
    redirect_to admin_user_path(@user)
  end
end
