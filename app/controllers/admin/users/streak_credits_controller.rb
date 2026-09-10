# Grants and revokes streak days a user did not code, for support cases where
# Hackatime lost the time. Progress is derived from streak_activities, so a
# credit on a missed day repairs the run behind it too.
class Admin::Users::StreakCreditsController < Admin::ApplicationController
  PANEL_FRAME = "admin_user_streak_credit_panel"

  def create
    @user = User.find(params[:user_id])
    authorize @user, :credit_streak_days?

    date = parse_date
    if date.nil?
      return respond_with_panel(alert: "Enter a valid date to credit.")
    elsif date > @user.streak_today_date
      return respond_with_panel(alert: "That day has not happened yet for #{@user.display_name}.")
    elsif params[:reason].blank?
      return respond_with_panel(alert: "A reason is required to credit a streak day.")
    end

    StreakActivity.credit!(user: @user, date: date, granted_by: current_user, reason: params[:reason])

    respond_with_panel(notice: "Credited #{date.to_fs(:long)} to #{@user.display_name}'s streak.")
  end

  def destroy
    @user = User.find(params[:user_id])
    authorize @user, :credit_streak_days?

    activity = @user.streak_activities.manually_credited.find(params[:id])
    activity.revoke_credit!

    respond_with_panel(notice: "Removed the credit for #{activity.activity_date.to_fs(:long)}.")
  end

  private

  # The form lives inside a turbo frame in the credit modal, so swap the panel
  # rather than redirecting: a redirect reloads the page and closes the dialog.
  # The html branch keeps the plain redirect for a submit made without Turbo.
  def respond_with_panel(notice: nil, alert: nil)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          PANEL_FRAME,
          partial: "admin/users/streak_credit_panel",
          locals: { user: @user, message: notice || alert, message_tone: alert ? :alert : :notice }
        )
      end
      format.html { redirect_back_to_user(notice ? { notice: notice } : { alert: alert }) }
    end
  end

  def parse_date
    Date.parse(params[:activity_date].to_s)
  rescue Date::Error
    nil
  end

  def redirect_back_to_user(flash_message)
    redirect_back(fallback_location: admin_user_path(@user), **flash_message)
  end
end
