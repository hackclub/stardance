class My::SettingsController < ApplicationController
  def update
    authorize :my, :update_settings?

    current_user.update(hcb_email: params[:hcb_email].presence)
    current_user.preference.update!(
      send_votes_to_slack: params[:send_votes_to_slack] == "1",
      leaderboard_optin: params[:leaderboard_optin] == "1",
      search_engine_indexing_off: params[:search_engine_indexing_off] == "1"
    )
    session[:streamer_mode] = params[:streamer_mode] == "1"
    session[:hackatime_indicator_hidden] = params[:hackatime_indicator_hidden] == "1"
    redirect_back fallback_location: root_path, notice: "Settings saved"
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
