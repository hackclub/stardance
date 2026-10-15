# == Schema Information
#
# Table name: mission_step_bodies
#
#  id              :bigint           not null, primary key
#  body            :text             default(""), not null
#  body_updated_at :datetime
#  language        :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  mission_step_id :bigint           not null
#
# Indexes
#
#  index_mission_step_bodies_on_mission_step_id  (mission_step_id)
#  index_mission_step_bodies_unique_language     (mission_step_id, lower((language)::text)) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (mission_step_id => mission_steps.id)
#
class Mission::StepBody < ApplicationRecord
  self.table_name = "mission_step_bodies"

  # No PaperTrail by design — the parent GuideVariant.body is already versioned
  # with the same content, so versioning here is redundant audit churn.

  belongs_to :step, class_name: "Mission::Step",
                    foreign_key: :mission_step_id,
                    inverse_of: :bodies

  validates :language, presence: true, length: { maximum: 64 },
                       uniqueness: { scope: :mission_step_id, case_sensitive: false }
  validates :body, presence: false

  before_save :stamp_body_updated_at, if: :body_changed?

  private

  def stamp_body_updated_at
    self.body_updated_at = Time.current
  end
end
