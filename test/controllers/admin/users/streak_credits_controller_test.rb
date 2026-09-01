require "test_helper"

# Helpers work the support queue where a wrongly missed streak day is reported,
# so they can credit a day even though the rest of their admin access is
# read-only.
class Admin::Users::StreakCreditsControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  setup do
    @helper = create_user(slack_id: "U_STREAK_HELPER", display_name: "streak_helper")
    @helper.grant_role!(:helper)
    @member = create_user(slack_id: "U_STREAK_MEMBER", display_name: "streak_member")
    @yesterday = @member.streak_today_date - 1.day
  end

  test "the credit control renders on the user page for a helper" do
    StreakActivity.credit!(user: @member, date: @yesterday, granted_by: @helper, reason: "Hackatime outage")
    sign_in @helper

    get admin_user_path(@member)

    assert_response :success
    assert_select "form[action=?]", admin_user_streak_credits_path(@member)
    assert_select ".admin-user-show__streak-credit", text: /Hackatime outage/
  end

  test "a helper credits a missed day" do
    sign_in @helper

    post admin_user_streak_credits_path(@member), params: {
      activity_date: @yesterday.to_s, reason: "Hackatime dropped the heartbeats"
    }

    assert_redirected_to admin_user_path(@member)
    activity = @member.streak_activities.find_by(activity_date: @yesterday)
    assert_predicate activity, :completed?
    assert_equal @helper, activity.manual_credit_by
    assert_equal "Hackatime dropped the heartbeats", activity.manual_credit_reason
  end

  test "crediting yesterday reconnects a run that had broken" do
    today = @member.streak_today_date
    StreakActivity.create!(user: @member, activity_date: today, coded_seconds: 400)
    StreakActivity.create!(user: @member, activity_date: today - 2.days, coded_seconds: 400)
    sign_in @helper

    post admin_user_streak_credits_path(@member), params: {
      activity_date: @yesterday.to_s, reason: "Hackatime outage"
    }

    assert_equal 3, @member.reload.current_streak
  end

  test "a day that has not happened yet cannot be credited" do
    sign_in @helper

    post admin_user_streak_credits_path(@member), params: {
      activity_date: (@member.streak_today_date + 1.day).to_s, reason: "too early"
    }

    assert_equal "That day has not happened yet for #{@member.display_name}.", flash[:alert]
    assert_empty @member.streak_activities
  end

  test "a reason is required" do
    sign_in @helper

    post admin_user_streak_credits_path(@member), params: { activity_date: @yesterday.to_s, reason: "" }

    assert_equal "A reason is required to credit a streak day.", flash[:alert]
    assert_empty @member.streak_activities
  end

  test "an unparseable date is refused rather than raising" do
    sign_in @helper

    post admin_user_streak_credits_path(@member), params: { activity_date: "not a date", reason: "oops" }

    assert_equal "Enter a valid date to credit.", flash[:alert]
    assert_empty @member.streak_activities
  end

  test "a member with no admin role never reaches the route" do
    sign_in create_user(slack_id: "U_STREAK_NOBODY", display_name: "streak_nobody")

    post admin_user_streak_credits_path(@member), params: {
      activity_date: @yesterday.to_s, reason: "please"
    }

    assert_response :not_found
    assert_empty @member.streak_activities
  end

  test "an admin role without support duties is refused" do
    shop_manager = create_user(slack_id: "U_STREAK_SHOP", display_name: "streak_shop")
    shop_manager.grant_role!(:shop_manager)
    sign_in shop_manager

    post admin_user_streak_credits_path(@member), params: {
      activity_date: @yesterday.to_s, reason: "please"
    }

    assert_response :forbidden
    assert_empty @member.streak_activities
  end

  test "revoking a credit leaves the real coding time behind" do
    activity = StreakActivity.create!(user: @member, activity_date: @yesterday, coded_seconds: 60)
    StreakActivity.credit!(user: @member, date: @yesterday, granted_by: @helper, reason: "granted in error")
    sign_in @helper

    delete admin_user_streak_credit_path(@member, activity)

    assert_redirected_to admin_user_path(@member)
    assert_not_predicate activity.reload, :completed?
    assert_equal 60, activity.coded_seconds
  end
end
