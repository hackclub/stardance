# The month calendar beside the manual date field when crediting a streak day,
# so a helper can see which days someone actually kept, and which are already
# credited, before picking the one to fix.
class Admin::Users::StreakCalendarsController < Admin::ApplicationController
  def show
    @user = User.find(params[:user_id])
    authorize @user, :credit_streak_days?

    render partial: "admin/users/streak_calendar",
           locals: { user: @user, date: requested_month },
           layout: false
  end

  private

  def requested_month
    first = StreakActivity::CALENDAR_FIRST_MONTH
    last = StreakActivity::CALENDAR_LAST_MONTH

    year = (params[:year] || Date.current.year).to_i.clamp(first.year, last.year)
    month = (params[:month] || Date.current.month).to_i.clamp(1, 12)
    Date.new(year, month, 1).clamp(first, last)
  end
end
