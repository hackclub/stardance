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
      @today = user.streak_today_date
      return unless ready?

      user.sync_streak_if_stale!
      @activities_by_date = user.streak_activities
        .for_range(activity_range)
        .index_by(&:activity_date)
    end

    def streak_count
      @streak_count ||= ready? ? user.current_streak : 0
    end

    def today_coded_minutes
      today_coded_seconds / 60
    end

    def today_completed?
      today_coded_seconds >= GOAL
    end

    def goal_minutes = GOAL / 60

    def week_days
      user.streak_week_activities(activities: @activities_by_date, today: @today)
    end

    def calendar_days
      user.streak_month_calendar(
        @today.year,
        @today.month,
        activities: @activities_by_date,
        today: @today
      )
    end

    def calendar_month_name
      @today.strftime("%B %Y")
    end

    def calendar_date = @today.beginning_of_month

    def next_day_at_iso = user.streak_next_day_at.iso8601
    def user_timezone = user.timezone.presence || "UTC"

    # Calendar paging bounds, as sortable YYYYMM keys for the Stimulus controller.
    def first_calendar_month = month_key(StreakActivity::CALENDAR_FIRST_MONTH)
    def last_calendar_month = month_key(StreakActivity::CALENDAR_LAST_MONTH)

    def sticky_streak = @sticky_streak ||= user.current_sticky_streak

    def sticky_started? = sticky_streak.present?

    def sticky_streaks_enabled? = user.sticky_streaks_enabled?

    def sticky_claimable_count = sticky_started? ? sticky_streak.claimable_days.size : 0

    private

    def today_coded_seconds
      @activities_by_date[@today]&.coded_seconds || 0
    end

    def activity_range
      week_start = @today.beginning_of_week(:sunday)
      calendar_start = @today.beginning_of_month.beginning_of_week(:sunday)
      calendar_end = @today.end_of_month.end_of_week(:sunday)

      [ week_start, calendar_start - 1.day ].min..[ week_start + 6.days, calendar_end + 1.day ].max
    end

    def month_key(date) = (date.year * 100) + date.month

    def linked_projects?
      user.hackatime_projects.where.not(project_id: nil).exists?
    end
  end
end
