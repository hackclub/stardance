class StickyStreaksController < ApplicationController
  before_action :require_user

  # Which run is on offer is decided server side, so nobody can post their way
  # into a second streak they have not earned.
  STARTED_NOTICE = {
    first: "Sticky Streak started! Code every day for the next #{StickyStreak::LENGTH} days.",
    retry: "Streak restarted! This is your last run, so keep it alive for all #{StickyStreak::LENGTH} days.",
    second: "Second streak started! Stickers are waiting on days #{StickyStreak::SECOND_REWARD_DAYS.to_sentence}."
  }.freeze

  def create
    authorize :sticky_streak, :start?

    unless current_user.sticky_streaks_enabled?
      return redirect_back fallback_location: root_path, alert: "Sticky Streaks aren't available yet."
    end

    unless current_user.hackatime_identity.present?
      return redirect_back fallback_location: root_path, alert: "Connect Hackatime before starting your Sticky Streak."
    end

    kind = current_user.startable_sticky_streak_kind
    unless kind
      return redirect_back fallback_location: root_path, alert: "You don't have a Sticky Streak to start right now."
    end

    current_user.sticky_streaks.create!(kind: kind, started_on: current_user.streak_today_date)
    redirect_back fallback_location: root_path, notice: STARTED_NOTICE.fetch(kind)
  rescue ActiveRecord::RecordNotUnique
    redirect_back fallback_location: root_path, alert: "That Sticky Streak has already started."
  end

  private

  def require_user
    redirect_to root_path unless current_user
  end
end
