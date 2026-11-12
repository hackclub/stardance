require 'rails_helper'

# == Schema Information
#
# Table name: project_mentions
#
#  id               :bigint           not null, primary key
#  approved_at      :datetime
#  approved_tier    :string
#  extra_links      :text
#  internal_notes   :text
#  metric_name      :string
#  metric_value     :integer
#  on_hold_at       :datetime
#  platform         :string
#  proposed_action  :string
#  proposed_tier    :string
#  rejected_at      :datetime
#  review_checklist :string           default([]), not null, is an Array
#  reviewer_notes   :text
#  submitter_notes  :text
#  url              :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  project_id       :bigint           not null
#  reviewer_id      :bigint
#
# Indexes
#
#  index_project_mentions_on_project_id   (project_id)
#  index_project_mentions_on_reviewer_id  (reviewer_id)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (reviewer_id => users.id)
#
RSpec.describe ProjectMention, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
