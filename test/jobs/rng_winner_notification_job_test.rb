require "test_helper"

class RngWinnerNotificationJobTest < ActiveSupport::TestCase
  setup do
    @user = create_user(slack_id: "U_RNG_JOB", display_name: "rng_job_user")
  end

  test "notifies a user holding the rng_winner achievement" do
    @user.award_achievement!(:rng_winner, notified: true)

    assert_difference -> { Notifications::RngWinner.count }, 1 do
      RngWinnerNotificationJob.perform_now
    end

    notification = Notifications::RngWinner.last
    assert_equal @user.id, notification.recipient_id
  end

  test "does not notify a user without the achievement" do
    assert_no_difference -> { Notifications::RngWinner.count } do
      RngWinnerNotificationJob.perform_now
    end
  end

  test "does not notify the same user twice across runs" do
    @user.award_achievement!(:rng_winner, notified: true)

    assert_difference -> { Notifications::RngWinner.count }, 1 do
      RngWinnerNotificationJob.perform_now
      RngWinnerNotificationJob.perform_now
    end
  end

  test "grants the achievement to a day's topper who never visited /achievements" do
    DailyRoll.create!(user: @user, value: 100, rolled_on: 2.days.ago.to_date)

    assert_difference -> { Notifications::RngWinner.count }, 1 do
      RngWinnerNotificationJob.perform_now
    end

    assert @user.reload.earned_achievement?(:rng_winner)
  end

  test "notifies with the winning roll as the record" do
    winning_roll = DailyRoll.create!(user: @user, value: 100, rolled_on: 2.days.ago.to_date)

    RngWinnerNotificationJob.perform_now

    assert_equal winning_roll, Notifications::RngWinner.last.record
  end
end
