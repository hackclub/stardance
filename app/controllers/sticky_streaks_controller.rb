class StickyStreaksController < ApplicationController
  before_action :require_user

  def create
    authorize :sticky_streak, :start?

    unless current_user.sticky_streaks_enabled?
      return redirect_back fallback_location: root_path, alert: "Sticky Streaks aren't available yet."
    end

    if current_user.sticky_streak.present?
      return redirect_back fallback_location: root_path, alert: "You have already started your Sticky Streak."
    end

    unless current_user.hackatime_identity.present?
      return redirect_back fallback_location: root_path, alert: "Connect Hackatime before starting your Sticky Streak."
    end

    current_user.create_sticky_streak!(started_on: current_user.streak_today_date)
    redirect_back fallback_location: root_path, notice: "Sticky Streak started! Code every day for the next #{StickyStreak::LENGTH} days."
  end

  private

  def require_user
    redirect_to root_path unless current_user
  end
end
