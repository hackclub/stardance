class Admin::Users::PresentableHardwareFlagsController < Admin::ApplicationController
  before_action :set_user

  # Granted after a showcase project (forms.hackclub.com/submit-showcase-project)
  # has been reviewed. Unlocks the Outpost Ticket via the achievement gate.
  def create
    authorize @user, :manage_feature_flags?

    @user.update!(has_presentable_hardware_project: true)
    @user.award_achievement!(:has_presentable_hardware_project, notified: true)
    log_change(true)

    redirect_to admin_user_path(@user),
                notice: "Marked #{@user.display_name} as having a presentable hardware project."
  end

  def destroy
    authorize @user, :manage_feature_flags?

    @user.update!(has_presentable_hardware_project: false)
    @user.achievements.where(achievement_slug: "has_presentable_hardware_project").destroy_all
    log_change(false)

    redirect_to admin_user_path(@user),
                notice: "Removed the presentable hardware project flag from #{@user.display_name}."
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
      object_changes: { has_presentable_hardware_project: [ !enabled, enabled ] }.to_json
    )
  end
end
