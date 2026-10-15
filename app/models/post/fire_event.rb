# == Schema Information
#
# Table name: post_fire_events
#
#  id         :bigint           not null, primary key
#  body       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Post::FireEvent < ApplicationRecord
  include Postable
  has_paper_trail

  # No longer needed since the body is hardcoded in the card component for compatibility with old stars
  # validates :body, presence: { message: "Message can't be blank" }
end
