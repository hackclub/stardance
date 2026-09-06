require "test_helper"

module Notifications
  class RngWinnerTest < ActiveSupport::TestCase
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
  end
end
