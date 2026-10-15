# == Schema Information
#
# Table name: mihi_activations
#
#  id                :bigint           not null, primary key
#  activated_on      :date             not null
#  activations_count :integer          default(1), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  user_id           :bigint           not null
#
# Indexes
#
#  index_mihi_activations_on_activated_on_and_user_id  (activated_on,user_id) UNIQUE
#  index_mihi_activations_on_user_id                   (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class MihiActivation < ApplicationRecord
  belongs_to :user
  has_paper_trail

  validates :activated_on, presence: true

  def self.record!(user:, now: Time.current)
    activation = create_or_find_by!(user: user, activated_on: now.in_time_zone("America/New_York").to_date)
    unless activation.previously_new_record?
      activation.with_lock do
        activation.update!(activations_count: activation.activations_count + 1)
      end
    end
    activation
  end
end
