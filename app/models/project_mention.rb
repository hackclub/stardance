# == Schema Information
#
# Table name: project_mentions
#
#  id              :bigint           not null, primary key
#  approved_at     :datetime
#  approved_tier   :string
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
  has_paper_trail

  belongs_to :project, -> { with_deleted }
  belongs_to :reviewer, class_name: "User", optional: true
  has_many :virality_decisions, dependent: :restrict_with_exception

  scope :awaiting_review, -> { where(approved_at: nil, rejected_at: nil) }
  scope :approved, -> { where.not(approved_at: nil) }

  validates :approved_tier, inclusion: { in: %w[good great] }, allow_nil: true

  validates :url, presence: true

  def status
    return :approved if approved_at?
    return :rejected if rejected_at?

    :pending
  end

  def evidence_urls
    url.to_s.split(/[\s,]+/).filter_map do |value|
      uri = URI.parse(value)
      value if uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      nil
    end
  end
end
