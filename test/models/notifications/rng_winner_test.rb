require "test_helper"

module Notifications
  # Each surface a notification type renders on is exercised here: the inbox
  # partial (a missing or broken one 500s /my/notifications for everyone
  # holding the type) and the Slack DM text.
  class RngWinnerTest < ActionDispatch::IntegrationTest
    setup do
      @user = create_user(slack_id: "U_RNG_MODEL", display_name: "rng_model_user")
    end

    test "is not aggregatable" do
      assert_not Notifications::RngWinner.aggregatable
    end

    test "slack_message includes the redeem link" do
      notification = Notifications::RngWinner.new(recipient: @user)
      assert_equal(
        "🎉 Congratulations! You got first place in the RNG! Redeem your prize here: " \
        "https://stardance.hackclub.com/shop/items/290",
        notification.slack_message
      )
    end

    test "slack_message includes the date of the winning roll, not just any grant date" do
      winning_roll = DailyRoll.create!(user: @user, value: 100, rolled_on: Date.new(2026, 7, 4))
      notification = Notifications::RngWinner.new(recipient: @user, record: winning_roll)

      assert_equal(
        "🎉 Congratulations! You got first place in the RNG on July 4, 2026! Redeem your prize here: " \
        "https://stardance.hackclub.com/shop/items/290",
        notification.slack_message
      )
    end

    test "preview_path links to the prize shop item" do
      notification = Notifications::RngWinner.new(recipient: @user)
      assert_equal "/shop/items/290", notification.preview_path
    end

    test "is registered" do
      assert_includes Notifications::Registry.all, Notifications::RngWinner
    end

    test "the inbox row renders" do
      winning_roll = DailyRoll.create!(user: @user, value: 100, rolled_on: Date.new(2026, 7, 4))
      Notifications::RngWinner.notify(recipient: @user, record: winning_roll)
      sign_in @user

      get my_notifications_path

      assert_response :success
      assert_select ".notifications-item__title", text: /first place in the RNG on July 4, 2026/
      assert_select ".notifications-item__title a[href=?]", my_achievements_path, text: "RNG"
      assert_select ".notifications-item__title a[href=?]", "/shop/items/290", text: "here"
    end

    test "the inbox row renders without a winning roll on record" do
      Notifications::RngWinner.notify(recipient: @user)
      sign_in @user

      get my_notifications_path

      assert_response :success
      assert_select ".notifications-item__title", text: /first place in the RNG\s*! Redeem your prize/
    end
  end
end
