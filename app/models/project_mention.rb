# == Schema Information
#
# Table name: project_mentions
#
#  id             :bigint           not null, primary key
#  approved_at    :datetime
#  metric_name    :string
#  metric_value   :integer
#  platform       :string
#  rejected_at    :datetime
#  reviewer_notes :text
#  url            :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  project_id     :bigint           not null
#  reviewer_id    :bigint
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
class ProjectMention < ApplicationRecord
  belongs_to :project
  belongs_to :reviewer, class_name: "User", optional: true
end
