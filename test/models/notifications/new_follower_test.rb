# == Schema Information
#
# Table name: notifications
#
#  id                 :bigint           not null, primary key
#  email_delivered_at :datetime
#  group_count        :integer          default(1), not null
#  group_key          :string
#  params             :jsonb            not null
#  priority           :integer          default("low"), not null
#  read_at            :datetime
#  record_type        :string
#  seen_at            :datetime
#  slack_enqueued_at  :datetime
#  type               :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  actor_id           :bigint
#  recipient_id       :bigint           not null
#  record_id          :bigint
#
# Indexes
#
#  index_notifications_on_actor_id                                (actor_id)
#  index_notifications_on_recipient_id                            (recipient_id)
#  index_notifications_on_recipient_id_and_created_at             (recipient_id,created_at)
#  index_notifications_on_recipient_id_and_group_key_and_read_at  (recipient_id,group_key,read_at) WHERE (group_key IS NOT NULL)
#  index_notifications_on_recipient_id_and_seen_at                (recipient_id,seen_at)
#  index_notifications_on_record_type_and_record_id               (record_type,record_id)
#  index_notifications_on_type_and_created_at                     (type,created_at)
#  index_notifications_unique_unread_aggregate                    (recipient_id,type,group_key) UNIQUE WHERE ((read_at IS NULL) AND (group_key IS NOT NULL))
#
# Foreign Keys
#
#  fk_rails_...  (actor_id => users.id) ON DELETE => nullify
#  fk_rails_...  (recipient_id => users.id) ON DELETE => cascade
#
require "test_helper"

module Notifications
  class NewFollowerTest < ActiveSupport::TestCase
    setup do
      @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
      @bob   = create_user(slack_id: "U_BOB",   display_name: "bob")
    end

    test "is low priority by default" do
      assert_equal :low, Notifications::NewFollower.default_priority
    end

    test "is aggregatable" do
      assert Notifications::NewFollower.aggregatable
    end

    test "builds a per-recipient group_key" do
      key = Notifications::NewFollower.build_group_key(recipient: @bob, actor: @alice, record: nil, params: {})
      assert_equal "user_followed:#{@bob.id}", key
    end

    test "slack_message renders with actor slack_id" do
      notification = Notifications::NewFollower.new(recipient: @bob, actor: @alice)
      assert_equal "✨ <@U_ALICE> just started following you on Stardance!", notification.slack_message
    end

    test "slack_message is nil when actor has no slack_id" do
      slackless = create_user(slack_id: nil, display_name: "ghost")
      notification = Notifications::NewFollower.new(recipient: @bob, actor: slackless)
      assert_nil notification.slack_message
    end
  end
end
