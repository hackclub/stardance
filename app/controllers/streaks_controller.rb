class StreaksController < ApplicationController
  before_action :require_user

  def month
    authorize :streak, :calendar?

    first_month = StreakActivity::CALENDAR_FIRST_MONTH
    last_month = StreakActivity::CALENDAR_LAST_MONTH

    year = (params[:year] || Date.current.year).to_i.clamp(first_month.year, last_month.year)
    month = (params[:month] || Date.current.month).to_i.clamp(1, 12)
    @date = Date.new(year, month, 1).clamp(first_month, last_month)

    @calendar_days = current_user.streak_month_calendar(@date.year, @date.month)
    @show_next = @date < last_month
    @show_prev = @date > first_month

    render partial: "streaks/month_grid",
           locals: { date: @date, calendar_days: @calendar_days, show_next: @show_next, show_prev: @show_prev },
           layout: false
  end

  def update_timezone
    authorize :streak, :calendar?

    tz = params[:timezone]
    if tz.present? && ActiveSupport::TimeZone[tz]
      current_user.update!(timezone: tz)
      head :ok
    else
      head :unprocessable_entity
    end
  end

  private

  def require_user
    redirect_to root_path unless current_user
  end
end
