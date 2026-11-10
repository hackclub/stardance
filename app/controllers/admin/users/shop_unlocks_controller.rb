class Admin::Users::ShopUnlocksController < Admin::ApplicationController
  before_action :set_user

  def create
    authorize @user, :unlock_shop?

    Flipper.enable(:shop_unlocked, @user)
    log_change("shop_unlocked", [ "locked", "unlocked" ])

    flash[:notice] = "Unlocked the shop for #{@user.display_name}."
    redirect_to admin_user_path(@user)
  end

  def destroy
    authorize @user, :unlock_shop?

    Flipper.disable(:shop_unlocked, @user)
    log_change("shop_relocked", [ "unlocked", "locked" ])

    flash[:notice] = "Removed the shop unlock for #{@user.display_name}."
    redirect_to admin_user_path(@user)
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def log_change(event, status)
    ::PaperTrail::Version.create!(
      item_type: "User",
      item_id: @user.id,
      event: event,
      whodunnit: current_user.id.to_s,
      object_changes: { shop_unlock: status }.to_json
    )
  end
end
