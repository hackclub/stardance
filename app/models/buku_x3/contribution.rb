# == Schema Information
#
# Table name: buku_x3_contributions
#
#  id             :bigint           not null, primary key
#  buku           :boolean          not null
#  minutes        :integer          default(0), not null
#  shipped_at     :datetime         not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  event_id       :bigint           not null
#  user_id        :bigint           not null
#  ysws_review_id :bigint           not null
#
# Indexes
#
#  index_buku_x3_contributions_on_event_id                     (event_id)
#  index_buku_x3_contributions_on_event_id_and_ysws_review_id  (event_id,ysws_review_id) UNIQUE
#  index_buku_x3_contributions_on_user_id                      (user_id)
#  index_buku_x3_contributions_on_ysws_review_id               (ysws_review_id)
#
# Foreign Keys
#
#  fk_rails_...  (event_id => buku_x3_events.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#  fk_rails_...  (ysws_review_id => certification_ysws_reviews.id) ON DELETE => cascade
#
class BukuX3::Contribution < ApplicationRecord
  has_paper_trail

  belongs_to :event, class_name: "BukuX3::Event"
  belongs_to :user
  belongs_to :ysws_review, class_name: "Certification::Ysws"

  validates :ysws_review_id, uniqueness: { scope: :event_id }
  validates :buku, inclusion: { in: [ true, false ] }
  validates :minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :shipped_at, presence: true

  def signed_minutes = buku? ? minutes : -minutes
end
