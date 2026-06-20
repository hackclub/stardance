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
class PostView < ApplicationRecord
  COUNTED_CACHE_TTL = 1.week

  belongs_to :post
  belongs_to :user

  def self.record_view(post, user)
    # Atomic SET NX: returns falsy when the key already exists, so repeat
    # views skip the database in a single cache round trip.
    return unless Rails.cache.write(counted_cache_key(post, user), true, unless_exist: true, expires_in: COUNTED_CACHE_TTL)

    result = insert({ post_id: post.id, user_id: user.id }, unique_by: [ :post_id, :user_id ], returning: :id)
    Post.increment_counter(:views_count, post.id) if result.rows.any?
  end

  def self.record_read(post, user)
    record_view(post, user)
    where(post: post, user: user, read_at: nil).update_all(read_at: Time.current)
  end

  def self.counted_cache_key(post, user)
    "post_views/counted/#{post.id}/#{user.id}"
  end
  private_class_method :counted_cache_key
end
