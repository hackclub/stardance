# == Schema Information
#
# Table name: project_fabricate_transfers
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  project_id :bigint           not null
#  user_id    :bigint           not null
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
# (fabricate.hackclub.com), Hack Club's newest hardware program. The project
# stays on Stardance, but it can no longer ask Stardance for funding, change
# stage or ship, so one design can't be funded by both programs.
#
# Nothing is sent to Fabricate. The owner follows fabricate_url, signs in with
# Hack Club there, and Fabricate pulls the project and their devlogs from our
# public API, importing it only once this record exists and the Slack ID it
# exposes matches theirs.
class Project::FabricateTransfer < ApplicationRecord
  BASE_URL = ENV.fetch("FABRICATE_BASE_URL", "https://fabricate.hackclub.com").freeze
  OVERVIEW_URL = "#{BASE_URL}/docs/overview".freeze

  has_paper_trail

  belongs_to :project
  belongs_to :user

  validates :project_id, uniqueness: true

  # Fabricate imports the project on the first visit and redirects to it after.
  def fabricate_url = "#{BASE_URL}/imports/stardance/#{project_id}"
end
