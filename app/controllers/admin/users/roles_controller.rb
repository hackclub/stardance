class Admin::Users::RolesController < Admin::ApplicationController
  before_action :set_user

  def create
    authorize @user, :manage_roles?

    role_name = params[:role_name]

    if role_name == "admin" && !current_user.super_admin?
      flash[:alert] = "Only super admins can promote to admin."
      return redirect_to admin_user_path(@user)
    end

    if role_name == "super_admin" && !current_user.super_admin?
      flash[:alert] = "#{current_user.display_name} is not in the sudoers file."
      return redirect_to admin_user_path(@user)
    end

    @user.grant_role!(role_name)

    ::PaperTrail::Version.create!(
      item_type: "User",
      item_id: @user.id,
      event: "role_promoted",
      whodunnit: current_user.id.to_s,
      object_changes: { role: role_name }.to_json
    )

    flash[:notice] = "User promoted to #{role_name.titleize}."
    redirect_to admin_user_path(@user)
  end

  def destroy
    authorize @user, :manage_roles?

    role_name = params[:name]

    if role_name == "super_admin" && !current_user.super_admin?
      flash[:alert] = "Only super admins can demote super admin."
      return redirect_to admin_user_path(@user)
    end

    if @user.has_role?(role_name)
      @user.remove_role!(role_name)

      ::PaperTrail::Version.create!(
        item_type: "User",
        item_id: @user.id,
        event: "role_demoted",
        whodunnit: current_user.id.to_s,
        object_changes: { role: role_name }.to_json
      )

      flash[:notice] = "User demoted from #{role_name.titleize}."
    else
      flash[:alert] = "Unable to demote user from #{role_name.titleize}."
    end

    redirect_to admin_user_path(@user)
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end
end
