# == Schema Information
#
# Table name: faqs
#
#  id         :bigint           not null, primary key
#  answer     :text             not null
#  position   :integer          default(0), not null
#  question   :text             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_faqs_on_position   (position)
#
class Faq < ApplicationRecord
  validates :question, :answer, presence: true
  scope :ordered, -> { order(:position) }

  before_create :set_position

  private

  def set_position
    self.position ||= (Faq.maximum(:position) || -1) + 1
  end
end
