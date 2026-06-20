# == Schema Information
#
# Table name: follows
#
#  id          :bigint           not null, primary key
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  followed_id :bigint           not null
#  follower_id :bigint           not null
#
# Indexes
#
#  index_follows_on_followed_id                  (followed_id)
#  index_follows_on_follower_id                  (follower_id)
#  index_follows_on_follower_id_and_followed_id  (follower_id,followed_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (followed_id => users.id)
#  fk_rails_...  (follower_id => users.id)
#
require "test_helper"

class FollowTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
    @bob   = create_user(slack_id: "U_BOB",   display_name: "bob")
  end

  test "follow creates link between two users" do
    follow = Follow.new(follower: @alice, followed: @bob)
    assert follow.save
  end

  test "rejects duplicate follows at the model level" do
    Follow.create!(follower: @alice, followed: @bob)
    duplicate = Follow.new(follower: @alice, followed: @bob)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:follower_id], "has already been taken"
  end

  test "rejects self-follow" do
    follow = Follow.new(follower: @alice, followed: @alice)
    assert_not follow.valid?
    assert_includes follow.errors[:followed_id], "can't follow yourself"
  end

  test "creates an in-app notification for the followed user" do
    assert_difference -> { @bob.notifications.count }, 1 do
      Follow.create!(follower: @alice, followed: @bob)
    end

    notification = @bob.notifications.last
    assert_instance_of Notifications::NewFollower, notification
    assert_equal @alice, notification.actor
  end
end
