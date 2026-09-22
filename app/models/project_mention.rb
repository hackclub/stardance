# == Schema Information
#
# Table name: project_mentions
#
#  id              :bigint           not null, primary key
#  approved_at     :datetime
#  metric_name     :string
#  metric_value    :integer
#  platform        :string
#  rejected_at     :datetime
#  reviewer_notes  :text
#  submitter_notes :text
#  url             :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  project_id      :bigint           not null
#  reviewer_id     :bigint
#
class ProjectMention < ApplicationRecord
  has_paper_trail

  belongs_to :project
  belongs_to :reviewer, class_name: "User", optional: true

  validates :url, presence: true
end
