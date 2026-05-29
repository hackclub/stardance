class Admin::Users::HackatimeSyncsController < Admin::ApplicationController
  def create
    @user = User.find(params[:user_id])
    authorize @user, :sync_hackatime?

    if @user.hackatime_identity
      @user.try_sync_hackatime_data!(force: true)
      flash[:notice] = "Hackatime data synced for #{@user.display_name}."
    else
      flash[:alert] = "User does not have a Hackatime identity."
    end

    redirect_to admin_user_path(@user)
  end
end
