# == Schema Information
#
# Table name: mission_prerequisites
#
#  id                      :bigint           not null, primary key
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  dependent_mission_id    :bigint           not null
#  prerequisite_mission_id :bigint           not null
#
# Indexes
#
#  idx_mission_prereqs_unique                              (prerequisite_mission_id,dependent_mission_id) UNIQUE
#  index_mission_prerequisites_on_dependent_mission_id     (dependent_mission_id)
#  index_mission_prerequisites_on_prerequisite_mission_id  (prerequisite_mission_id)
#
# Foreign Keys
#
#  fk_rails_...  (dependent_mission_id => missions.id)
#  fk_rails_...  (prerequisite_mission_id => missions.id)
#
class Mission::Prerequisite < ApplicationRecord
  self.table_name = "mission_prerequisites"

  belongs_to :prerequisite_mission, class_name: "Mission"
  belongs_to :dependent_mission, class_name: "Mission"

  validates :prerequisite_mission_id, uniqueness: { scope: :dependent_mission_id }
end
