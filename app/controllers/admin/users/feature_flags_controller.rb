class Admin::Users::FeatureFlagsController < Admin::ApplicationController
  before_action :set_user

  def create
    authorize @user, :manage_feature_flags?

    feature = params[:feature].to_sym
    Flipper.enable(feature, @user)

    ::PaperTrail::Version.create!(
      item_type: "User",
      item_id: @user.id,
      event: "flipper_enable",
      whodunnit: current_user.id,
      object_changes: { feature: [ nil, feature.to_s ], status: [ "disabled", "enabled" ] }.to_json
    )

    flash[:notice] = "Enabled #{feature} for #{@user.display_name}."
    redirect_to admin_user_path(@user)
  end

  def destroy
    authorize @user, :manage_feature_flags?

    feature = params[:feature].to_sym
    Flipper.disable(feature, @user)

    ::PaperTrail::Version.create!(
      item_type: "User",
      item_id: @user.id,
      event: "flipper_disable",
      whodunnit: current_user.id,
      object_changes: { feature: [ feature.to_s, nil ], status: [ "enabled", "disabled" ] }.to_json
    )

    flash[:notice] = "Disabled #{feature} for #{@user.display_name}."
    redirect_to admin_user_path(@user)
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end
end
