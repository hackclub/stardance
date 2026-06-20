# == Schema Information
#
# Table name: post_views
#
#  id         :bigint           not null, primary key
#  read_at    :datetime
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  post_id    :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_post_views_on_post_id_and_user_id  (post_id,user_id) UNIQUE
#  index_post_views_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (post_id => posts.id)
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

class PostViewTest < ActiveSupport::TestCase
  setup do
    @post = posts(:one)
    @user = users(:two)
  end

  test "record_view creates one row and one count per user" do
    assert_difference -> { PostView.count } => 1, -> { @post.reload.views_count } => 1 do
      2.times { PostView.record_view(@post, @user) }
    end
  end

  test "record_view counts distinct users separately" do
    PostView.record_view(@post, users(:one))
    PostView.record_view(@post, users(:two))

    assert_equal 2, @post.reload.views_count
  end

  test "record_view skips the database once the cache guard is warm" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    PostView.record_view(@post, @user)
    PostView.where(post: @post, user: @user).delete_all
    PostView.record_view(@post, @user)

    assert_empty PostView.where(post: @post, user: @user)
    assert_equal 1, @post.reload.views_count
  ensure
    Rails.cache = original_cache
  end

  test "record_read creates the view and stamps read_at" do
    PostView.record_read(@post, @user)

    assert_predicate PostView.find_by!(post: @post, user: @user).read_at, :present?
    assert_equal 1, @post.reload.views_count
  end

  test "record_read does not move an existing read_at" do
    PostView.record_read(@post, @user)
    first_read_at = PostView.find_by!(post: @post, user: @user).read_at

    travel 1.hour do
      PostView.record_read(@post, @user)
    end

    assert_equal first_read_at, PostView.find_by!(post: @post, user: @user).read_at
  end
end
