require "test_helper"

module Notifications
  class DevlogQuoteRepostedTest < ActiveSupport::TestCase
    setup do
      @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
      @bob   = create_user(slack_id: "U_BOB", display_name: "bob")
    end

    test "is low priority by default" do
      assert_equal :low, Notifications::DevlogQuoteReposted.default_priority
    end

    test "is not aggregatable so each quote shows its own text" do
      assert_not Notifications::DevlogQuoteReposted.aggregatable
    end

    test "slack_message renders with actor slack_id" do
      notification = Notifications::DevlogQuoteReposted.new(recipient: @bob, actor: @alice)
      assert_equal "🔁 <@U_ALICE> quote-reposted your devlog on Stardance!", notification.slack_message
    end

    test "slack_message is nil when actor has no slack_id" do
      slackless = create_user(slack_id: nil, display_name: "ghost")
      notification = Notifications::DevlogQuoteReposted.new(recipient: @bob, actor: slackless)
      assert_nil notification.slack_message
    end

    test "is registered" do
      assert_includes Notifications::Registry.all, Notifications::DevlogQuoteReposted
    end
  end
end
