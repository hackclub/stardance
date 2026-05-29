class Admin::Users::YswsOverridesController < Admin::ApplicationController
  def update
    @user = User.find(params[:user_id])
    authorize @user, :manage_ysws_override?

    raw_override = params[:manual_ysws_override]
    new_override = raw_override == "true" ? true : nil
    old_override = @user.manual_ysws_override
    @user.manual_ysws_override = new_override

    if @user.save
      ::PaperTrail::Version.create!(
        item_type: "User",
        item_id: @user.id,
        event: "manual_ysws_override_set",
        whodunnit: current_user.id.to_s,
        object_changes: { manual_ysws_override: [ old_override, new_override ] }.to_json
      )

      if @user.eligible_for_shop?
        Shop::ProcessVerifiedOrdersJob.perform_later(@user.id)
      end

      flash[:notice] = "YSWS eligibility overridden, now #{@user.ysws_eligible? ? 'eligible' : 'ineligible'}."
    else
      flash[:alert] = "Failed to update override"
    end

    redirect_to admin_user_path(@user)
  end
end
