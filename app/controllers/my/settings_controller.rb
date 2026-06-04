class My::SettingsController < ApplicationController
  def update
    authorize :my, :update_settings?

    current_user.update(hcb_email: params[:hcb_email].presence)
    current_user.preference.update!(
      send_votes_to_slack: params[:send_votes_to_slack] == "1",
      leaderboard_optin: params[:leaderboard_optin] == "1",
      stardust_balance_notifications: params[:stardust_balance_notifications] == "1",
      send_notifications_for_followed_projects: params[:send_notifications_for_followed_projects] == "1",
      send_notifications_for_new_followers: params[:send_notifications_for_new_followers] == "1",
      send_notifications_for_new_comments: params[:send_notifications_for_new_comments] == "1",
      search_engine_indexing_off: params[:search_engine_indexing_off] == "1"
    )
    session[:streamer_mode] = params[:streamer_mode] == "1"
    redirect_back fallback_location: root_path, notice: "Settings saved"
  end

  def roll_api_key
    unless current_user&.hack_club_identity.present?
      return redirect_back fallback_location: root_path, alert: "Connect a Hack Club account to generate an API key"
    end
    authorize :my, :update_settings?
    current_user.reroll_api_key!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "api_key",
          partial: "users/api_key",
          locals: { user: current_user, just_generated: true }
        )
      end
      format.html { redirect_back fallback_location: root_path, notice: "API key rotated" }
    end
  end

  def toggle_streamer_mode
    session[:streamer_mode] = params.key?(:enable) ? params[:enable] == "true" : !session[:streamer_mode]
    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  private

  def require_login
    redirect_to root_path, alert: "Please log in first" and return unless current_user
  end
end
