require "test_helper"

module Notifications
  class DevlogLikedTest < ActiveSupport::TestCase
    setup do
      @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
      @bob   = create_user(slack_id: "U_BOB", display_name: "bob")
    end

    test "is low priority by default" do
      assert_equal :low, Notifications::DevlogLiked.default_priority
    end

    test "is aggregatable" do
      assert Notifications::DevlogLiked.aggregatable
    end

    test "builds a per-devlog group_key" do
      record = Struct.new(:id).new(42)
      key = Notifications::DevlogLiked.build_group_key(recipient: @bob, actor: @alice, record: record, params: {})
      assert_equal "devlog_liked:42:#{@bob.id}", key
    end

    test "slack_message renders with actor slack_id" do
      notification = Notifications::DevlogLiked.new(recipient: @bob, actor: @alice)
      assert_equal "❤️ <@U_ALICE> liked your devlog on Stardance!", notification.slack_message
    end

    test "slack_message is nil when actor has no slack_id" do
      slackless = create_user(slack_id: nil, display_name: "ghost")
      notification = Notifications::DevlogLiked.new(recipient: @bob, actor: slackless)
      assert_nil notification.slack_message
    end

    test "is registered" do
      assert_includes Notifications::Registry.all, Notifications::DevlogLiked
    end
  end
end
