class MyController < ApplicationController
  before_action :require_login

  def balance
    unless turbo_frame_request?
      redirect_to root_path
      return
    end

    @balance = current_user.ledger_entries.includes(:ledgerable).order(created_at: :desc)
  end

  def update_settings
    current_user.update(
      hcb_email: params[:hcb_email].presence,
      send_votes_to_slack: params[:send_votes_to_slack] == "1",
      leaderboard_optin: params[:leaderboard_optin] == "1",
      slack_balance_notifications: params[:slack_balance_notifications] == "1",
      send_notifications_for_followed_devlogs: params[:send_notifications_for_followed_devlogs] == "1",
      send_notifications_for_new_followers: params[:send_notifications_for_new_followers] == "1",
      send_notifications_for_new_comments: params[:send_notifications_for_new_comments] == "1",
      special_effects_enabled: params[:special_effects_enabled] == "1",
      search_engine_indexing_off: params[:search_engine_indexing_off] == "1"
    )
    redirect_back fallback_location: root_path, notice: "Settings saved"
  end

  def unlink_club
    current_user.update!(club_name: nil, club_link: nil)
    redirect_back fallback_location: root_path, notice: "Club unlinked"
  end

  def cookie_click
    clicks = params[:clicks].to_i.clamp(1, 100)
    current_user.increment!(:cookie_clicks, clicks)
    head :ok
  end

  def dismiss_thing
    thing_name = params[:thing_name]
    return head :bad_request unless thing_name.present?

    current_user.dismiss_thing!(thing_name)
    head :ok
  rescue StandardError => e
    Rails.logger.error("Error dismissing thing: #{e.message}")
    head :internal_server_error
  end

  private

  def require_login
    redirect_to root_path, alert: "Please log in first" and return unless current_user
  end
end
