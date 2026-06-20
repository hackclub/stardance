# == Schema Information
#
# Table name: post_reposts
#
#  id               :bigint           not null, primary key
#  body             :string
#  deleted_at       :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  original_post_id :bigint           not null
#  user_id          :bigint           not null
#
# Indexes
#
#  index_post_reposts_active_unique        (original_post_id,user_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_post_reposts_on_deleted_at        (deleted_at)
#  index_post_reposts_on_original_post_id  (original_post_id)
#  index_post_reposts_on_user_id           (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (original_post_id => posts.id)
#  fk_rails_...  (user_id => users.id)
#
class Post::Repost < ApplicationRecord
  include Postable
  include SoftDeletable
  has_paper_trail

  belongs_to :original_post, class_name: "Post", counter_cache: :reposts_count
  belongs_to :user

  validates :body, length: { maximum: Post::Devlog::BODY_MAX_LENGTH }, allow_blank: true
  validates :original_post_id, uniqueness: { scope: :user_id, conditions: -> { not_deleted } }
  validate :original_post_is_visible_devlog

  after_create_commit :send_gorse_repost_later
  after_create_commit :notify_devlog_author
  after_update :update_reposts_count_on_soft_delete

  private
  def send_gorse_repost_later
    send_gorse_feedback_later(user: user, item: original_post, feedback_type: :repost, timestamp: created_at)
  end

  # Notify the reposted devlog's author. A quote-repost (one that carries its
  # own body) gets its own standalone notification so the quote text shows;
  # plain reposts use the aggregated type. Notification.notify skips
  # self-reposts (actor == recipient) on its own.
  def notify_devlog_author
    author = original_post&.user
    devlog = original_post&.postable
    return if author.nil? || !devlog.is_a?(Post::Devlog)

    if body.present?
      Notifications::DevlogQuoteReposted.notify(recipient: author, actor: user, record: self)
    else
      Notifications::DevlogReposted.notify(recipient: author, actor: user, record: devlog)
    end
  end

  def original_post_is_visible_devlog
    if original_post.present? && user.present?
      if original_post.postable_type != "Post::Devlog"
        errors.add(:original_post, "must be a devlog")
      elsif original_post.postable.blank? || original_post.postable.deleted?
        errors.add(:original_post, "must be available")
      elsif !Post.visible_to(user).where(id: original_post.id).exists?
        errors.add(:original_post, "must be visible")
      end
    end
  end

  def update_reposts_count_on_soft_delete
    return unless saved_change_to_deleted_at?

    delta = deleted_at.present? ? -1 : 1
    Post.update_counters(original_post_id, reposts_count: delta)
  end
end
