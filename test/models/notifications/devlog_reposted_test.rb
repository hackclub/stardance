require "test_helper"

module Notifications
  class DevlogRepostedTest < ActiveSupport::TestCase
    setup do
      @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
      @bob   = create_user(slack_id: "U_BOB", display_name: "bob")
    end

    test "is low priority by default" do
      assert_equal :low, Notifications::DevlogReposted.default_priority
    end

    test "is aggregatable" do
      assert Notifications::DevlogReposted.aggregatable
    end

    test "builds a per-devlog group_key" do
      record = Struct.new(:id).new(42)
      key = Notifications::DevlogReposted.build_group_key(recipient: @bob, actor: @alice, record: record, params: {})
      assert_equal "devlog_reposted:42:#{@bob.id}", key
    end

    test "slack_message renders with actor slack_id" do
      notification = Notifications::DevlogReposted.new(recipient: @bob, actor: @alice)
      assert_equal "🔁 <@U_ALICE> reposted your devlog on Stardance!", notification.slack_message
    end

    test "slack_message is nil when actor has no slack_id" do
      slackless = create_user(slack_id: nil, display_name: "ghost")
      notification = Notifications::DevlogReposted.new(recipient: @bob, actor: slackless)
      assert_nil notification.slack_message
    end

    test "is registered" do
      assert_includes Notifications::Registry.all, Notifications::DevlogReposted
    end
  end
end
