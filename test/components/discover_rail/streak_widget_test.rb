require "test_helper"

class DiscoverRail::StreakWidgetTest < ViewComponent::TestCase
  setup do
    @user = users(:three)
    @user.update!(onboarded_at: Time.current, timezone: "America/New_York")

    today = @user.streak_today_date
    StreakActivity.create!(user: @user, activity_date: today, coded_seconds: 240)
    StreakActivity.create!(user: @user, activity_date: today - 1.day, coded_seconds: 300)
  end

  teardown do
    @user.streak_activities.destroy_all
    @user.update!(onboarded_at: nil, timezone: nil)
  end

  test "loads streak activities once for the complete widget" do
    component = DiscoverRail::StreakWidget.new(user: @user)
    activity_queries = []
    record_activity_query = lambda do |*args|
      sql = args.last[:sql]
      activity_queries << sql if sql.match?(/FROM "streak_activities"/i)
    end

    component.stub(:ready?, true) do
      component.stub(:setup_needed?, false) do
        component.stub(:linking_needed?, false) do
          @user.stub(:sync_streak_if_stale!, nil) do
            ActiveSupport::Notifications.subscribed(record_activity_query, "sql.active_record") do
              render_inline(component)
            end
          end
        end
      end
    end

    assert_equal 1, activity_queries.length
    assert_text "4 / 5 minutes today"
    assert_selector ".streak-widget__day", count: 7
  end

  test "renders the setup state without loading activities" do
    activity_queries = []
    record_activity_query = lambda do |*args|
      sql = args.last[:sql]
      activity_queries << sql if sql.match?(/FROM "streak_activities"/i)
    end

    ActiveSupport::Notifications.subscribed(record_activity_query, "sql.active_record") do
      render_inline(DiscoverRail::StreakWidget.new(user: @user))
    end

    assert_text "Connect Hackatime"
    assert_empty activity_queries
  end
end
