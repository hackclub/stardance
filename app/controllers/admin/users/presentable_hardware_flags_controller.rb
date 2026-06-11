class Admin::Users::PresentableHardwareFlagsController < Admin::ApplicationController
  before_action -> { head :not_found unless Project.hardware_flow_enabled? }
  before_action :set_user

  # Granted after a showcase project (forms.hackclub.com/submit-showcase-project)
  # has been reviewed. Unlocks the Outpost Ticket via the achievement gate.
  def create
    authorize @user, :manage_feature_flags?

    @user.update!(manual_outpost_ticket_approval: params[:approval_url])
    @user.award_achievement!(:manual_outpost_ticket_approval, notified: true)
    log_change(true)

    redirect_to admin_user_path(@user),
                notice: "Approved Outpost Ticket for #{@user.display_name}."
  end

  def destroy
    authorize @user, :manage_feature_flags?

    @user.update!(manual_outpost_ticket_approval: nil)
    @user.achievements.where(achievement_slug: "manual_outpost_ticket_approval").destroy_all
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
      object_changes: { manual_outpost_ticket_approval: [ !enabled, enabled ] }.to_json
    )
  end
end
