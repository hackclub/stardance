require "test_helper"

module Notifications
  class AchievementEarnedTest < ActiveSupport::TestCase
    setup do
      @user = create_user(slack_id: "U_USER", display_name: "earner")
    end

    test "is not aggregatable" do
      assert_not Notifications::AchievementEarned.aggregatable
    end

    test "resolves the achievement from a slug in params" do
      notification = Notifications::AchievementEarned.new(recipient: @user, params: { "achievement_slug" => "referral_2" })
      assert_equal "2 Friends Referred", notification.achievement&.name
    end

    test "slack_message names the achievement" do
      notification = Notifications::AchievementEarned.new(recipient: @user, params: { "achievement_slug" => "referral_2" })
      assert_equal "🏆 You earned the *2 Friends Referred* achievement on Stardance!", notification.slack_message
    end

    test "slack_message is nil with an unknown achievement" do
      notification = Notifications::AchievementEarned.new(recipient: @user, params: { "achievement_slug" => "nope" })
      assert_nil notification.slack_message
    end

    test "is registered" do
      assert_includes Notifications::Registry.all, Notifications::AchievementEarned
    end

    test "is not sent for rng_winner, which has its own dedicated notification" do
      assert_no_difference -> { Notifications::AchievementEarned.count } do
        @user.award_achievement!(:rng_winner)
      end
    end

    test "is still sent for other achievements" do
      assert_difference -> { Notifications::AchievementEarned.count }, 1 do
        @user.award_achievement!(:super_star)
      end
    end
  end
end
