# == Schema Information
#
# Table name: likes
#
#  id            :bigint           not null, primary key
#  likeable_type :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  likeable_id   :bigint           not null
#  user_id       :bigint           not null
#
# Indexes
#
#  index_likes_on_likeable                                   (likeable_type,likeable_id)
#  index_likes_on_user_id                                    (user_id)
#  index_likes_on_user_id_and_likeable_type_and_likeable_id  (user_id,likeable_type,likeable_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Like < ApplicationRecord
  has_paper_trail

  belongs_to :likeable, polymorphic: true, counter_cache: true
  belongs_to :user

  validates :user_id, uniqueness: { scope: [ :likeable_type, :likeable_id ], message: "has already liked this" }

  after_create_commit :send_gorse_like_later

  private
    def send_gorse_like_later
      if likeable_type == "Post::Devlog" && likeable&.post.present?
        send_gorse_feedback_later(user: user, item: likeable.post, feedback_type: :like, timestamp: created_at)
      end
    end
end
