# == Schema Information
#
# Table name: project_fabricate_transfers
#
#  id                   :bigint           not null, primary key
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  fabricate_project_id :bigint           not null
#  project_id           :bigint           not null
#  user_id              :bigint           not null
#
# Indexes
#
#  index_project_fabricate_transfers_on_project_id  (project_id) UNIQUE
#  index_project_fabricate_transfers_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (user_id => users.id)
#
# A design-stage hardware project its owner moved to Fabricate
# (fabricate.hackclub.com). The project stays on Stardance, but it can no
# longer ask Stardance for funding or change stage, so one design can't be
# funded by both programs.
class Project::FabricateTransfer < ApplicationRecord
  has_paper_trail

  belongs_to :project
  belongs_to :user

  validates :fabricate_project_id, presence: true
  validates :project_id, uniqueness: true

  def fabricate_url = FabricateService.project_url(fabricate_project_id)
end
