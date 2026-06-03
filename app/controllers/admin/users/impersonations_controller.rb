class Admin::Users::ImpersonationsController < Admin::ApplicationController
  skip_before_action :prevent_admin_access_while_impersonating, only: [ :destroy ]

  def create
    @user = User.find(params[:user_id])
    authorize @user, :impersonate?

    admin_user = current_user
    session[:impersonator_user_id] = admin_user.id
    sign_in_user(@user, auth_level: @user.hca_linked? ? "hca" : "guest")
    pundit_reset!
    authorize @user, :impersonate?

    ::PaperTrail::Version.create!(
      item_type: "User",
      item_id: @user.id,
      event: "impersonation_started",
      whodunnit: admin_user.id.to_s,
      object_changes: {
        impersonated_by: admin_user.id,
        impersonated_by_name: admin_user.display_name
      }.to_json
    )

    flash[:notice] = "Now impersonating #{@user.display_name}. You can stop impersonation from the banner at the top."
    redirect_to root_path
  end

  def destroy
    authorize current_user, :stop_impersonating?
    impersonated_user = current_user
    admin_user = real_user

    if admin_user && impersonated_user
      ::PaperTrail::Version.create!(
        item_type: "User",
        item_id: impersonated_user.id,
        event: "impersonation_stopped",
        whodunnit: admin_user.id.to_s,
        object_changes: {
          stopped_by: admin_user.id,
          stopped_by_name: admin_user.display_name
        }.to_json
      )
    end

    sign_in_user(admin_user, auth_level: "hca")
    session.delete(:impersonator_user_id)
    @current_user = admin_user
    pundit_reset!
    authorize admin_user, :stop_impersonating?
    flash[:notice] = "Stopped impersonating #{impersonated_user&.display_name}."

    redirect_to admin_users_path
  end
end
