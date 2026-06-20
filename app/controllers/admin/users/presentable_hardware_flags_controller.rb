class Admin::Users::PresentableHardwareFlagsController < Admin::ApplicationController
  before_action -> { head :not_found unless Flipper.enabled?(:hardware_flow, current_user) }
  before_action :set_user

  # Manual toggle: an admin grants this once a hardware project is presentable.
  # Awards the achievement that unlocks the Outpost Ticket via the shop gate.
  def create
    authorize @user, :manage_feature_flags?

    @user.award_achievement!(:manual_outpost_ticket_approval, notified: true)
    log_change(true)

    redirect_to admin_user_path(@user),
                notice: "Approved Outpost Ticket for #{@user.display_name}."
  end

  def destroy
    authorize @user, :manage_feature_flags?

    @user.revoke_achievement!(:manual_outpost_ticket_approval)
    log_change(false)

    redirect_to admin_user_path(@user),
                notice: "Removed Outpost Ticket approval from #{@user.display_name}."
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def log_change(enabled)
    ::PaperTrail::Version.create!(
      item_type: "User",
      item_id: @user.id,
      event: enabled ? "presentable_hardware_enable" : "presentable_hardware_disable",
      whodunnit: current_user.id,
      object_changes: { outpost_ticket_approved: [ !enabled, enabled ] }.to_json
    )
  end
end
