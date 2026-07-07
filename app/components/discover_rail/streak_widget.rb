# frozen_string_literal: true

module DiscoverRail
  class StreakWidget < BaseWidget
    register_as :streak

    GOAL = StreakActivity::DAILY_GOAL_SECONDS

    def deferred?
      true
    end

    def deferred_frame_id
      "discover_rail_streak"
    end

    def deferred_path_helper
      :streak_home_discover_rail_path
    end

    def render?
      user.present? && user.onboarded?
    end

    def setup_needed?
      !user.hackatime_identity.present?
    end

    def linking_needed?
      user.hackatime_identity.present? && !linked_projects?
    end

    def ready?
      !setup_needed? && !linking_needed?
    end

    def before_render
      user.sync_streak_if_stale! if ready?
    end

    def streak_count
      @streak_count ||= ready? ? user.current_streak : 0
    end

    def today_coded_minutes
      (user.streak_today_activity&.coded_seconds || 0) / 60
    end

    def today_completed?
      (user.streak_today_activity&.coded_seconds || 0) >= GOAL
    end

    def goal_minutes = GOAL / 60

    def week_days = user.streak_week_activities

    def calendar_days
      today = user.streak_today_date
      user.streak_month_calendar(today.year, today.month)
    end

    def calendar_month_name
      user.streak_today_date.strftime("%B %Y")
    end

    def next_day_at_iso = user.streak_next_day_at.iso8601
    def user_timezone = user.timezone.presence || "UTC"

    private

    def linked_projects?
      user.hackatime_projects.where.not(project_id: nil).exists?
    end
  end
end
