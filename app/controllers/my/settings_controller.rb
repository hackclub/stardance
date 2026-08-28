class My::SettingsController < ApplicationController
  def update
    authorize :my, :update_settings?

    current_user.update(hcb_email: params[:hcb_email].presence)

    pref_attrs = {
      send_votes_to_slack: params[:send_votes_to_slack] == "1",
      leaderboard_optin: params[:leaderboard_optin] == "1",
      search_engine_indexing_off: params[:search_engine_indexing_off] == "1"
    }

    if current_user.preference.has_attribute?(:streak_slack_status_enabled)
      new_val = params[:streak_slack_status_enabled] == "1"
      old_val = current_user.preference.streak_slack_status_enabled
      pref_attrs[:streak_slack_status_enabled] = new_val

      current_user.preference.update!(pref_attrs)

      if new_val != old_val
        if new_val
          SetSlackStreakStatusJob.perform_later(current_user.id)
        else
          ClearSlackStreakStatusJob.perform_later(current_user.id)
        end
      end
    else
      current_user.preference.update!(pref_attrs)
    end
    session[:streamer_mode] = params[:streamer_mode] == "1"
    redirect_back fallback_location: root_path, notice: "Settings saved"
  end

  def toggle_streamer_mode
    session[:streamer_mode] = params.key?(:enable) ? params[:enable] == "true" : !session[:streamer_mode]
    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def regenerate_api_key
    current_user.regenerate_api_key
    warning = "API key regenerated."

    respond_to do |format|
      format.turbo_stream do
        flash.now[:warning] = warning
        render turbo_stream: [
          turbo_stream.replace("api-key-section", partial: "my/settings/api_key", locals: { user: current_user }),
          turbo_stream.update("flash-region", partial: "shared/flash")
        ]
      end
      format.html { redirect_back fallback_location: root_path, flash: { warning: warning } }
    end
  end

  private

  def require_login
    redirect_to root_path, alert: "Please log in first" and return unless current_user
  end
end
