# == Schema Information
#
# Table name: comments
#
#  id               :bigint           not null, primary key
#  body             :text             not null
#  commentable_type :string           not null
#  deleted_at       :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  commentable_id   :bigint           not null
#  user_id          :bigint           not null
#
# Indexes
#
#  index_comments_on_commentable                 (commentable_type,commentable_id)
#  index_comments_on_commentable_and_created_at  (commentable_type,commentable_id,created_at)
#  index_comments_on_deleted_at                  (deleted_at)
#  index_comments_on_user_id                     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Comment < ApplicationRecord
  BODY_MAX_LENGTH = 5_000

  include SoftDeletable
  include Mentionable
  has_paper_trail

  belongs_to :commentable, polymorphic: true, counter_cache: true
  belongs_to :user

  validates :body, presence: true, length: { maximum: BODY_MAX_LENGTH }

  after_create :notify_slack_channel
  after_create_commit :send_gorse_comment_later
  after_update :update_counter_cache_on_soft_delete

  private

  def notify_slack_channel
    PostCreationToSlackJob.perform_later(self)
  end

  def update_counter_cache_on_soft_delete
    return unless saved_change_to_deleted_at?

    delta = deleted_at.present? ? -1 : 1
    commentable.class.update_counters(commentable_id, comments_count: delta)
  end

  def send_gorse_comment_later
    if commentable_type == "Post::Devlog" && commentable&.post.present?
      send_gorse_feedback_later(user: user, item: commentable.post, feedback_type: :comment, timestamp: created_at)
    end
  end
end
