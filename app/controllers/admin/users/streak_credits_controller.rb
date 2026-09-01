# Grants and revokes streak days a user did not code, for support cases where
# Hackatime lost the time. Progress is derived from streak_activities, so a
# credit on a missed day repairs the run behind it too.
class Admin::Users::StreakCreditsController < Admin::ApplicationController
  def create
    @user = User.find(params[:user_id])
    authorize @user, :credit_streak_days?

    date = parse_date
    if date.nil?
      return redirect_back_to_user(alert: "Enter a valid date to credit.")
    elsif date > @user.streak_today_date
      return redirect_back_to_user(alert: "That day has not happened yet for #{@user.display_name}.")
    elsif params[:reason].blank?
      return redirect_back_to_user(alert: "A reason is required to credit a streak day.")
    end

    StreakActivity.credit!(user: @user, date: date, granted_by: current_user, reason: params[:reason])

    redirect_back_to_user(notice: "Credited #{date.to_fs(:long)} to #{@user.display_name}'s streak.")
  end

  def destroy
    @user = User.find(params[:user_id])
    authorize @user, :credit_streak_days?

    activity = @user.streak_activities.manually_credited.find(params[:id])
    activity.revoke_credit!

    redirect_back_to_user(notice: "Removed the credit for #{activity.activity_date.to_fs(:long)}.")
  end

  private

  def parse_date
    Date.parse(params[:activity_date].to_s)
  rescue Date::Error
    nil
  end

  def redirect_back_to_user(flash_message)
    redirect_back(fallback_location: admin_user_path(@user), **flash_message)
  end
end
