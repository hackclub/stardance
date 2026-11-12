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
class ProjectMention < ApplicationRecord
  # Reviewer judgement calls. Threshold and ship status are checked by the
  # decision itself, so they are not part of the manual checklist.
  ELIGIBILITY_CHECKS = [
    "README credits Hack Club",
    "Original work",
    "Built during Stardance",
    "Outside Hack Club",
    "Organic engagement"
  ].freeze

  has_paper_trail

  belongs_to :project, -> { with_deleted }
  belongs_to :reviewer, class_name: "User", optional: true
  has_many :virality_decisions, dependent: :restrict_with_exception

  scope :awaiting_review, -> { where(approved_at: nil, rejected_at: nil) }
  scope :approved, -> { where.not(approved_at: nil) }
  scope :on_hold, -> { where.not(on_hold_at: nil) }
  scope :not_on_hold, -> { where(on_hold_at: nil) }
  # A verdict reached outside the platform (the Airtable import). Nothing is
  # applied until a reviewer confirms it through a normal decision.
  scope :proposed, -> { where.not(proposed_action: nil) }
  scope :unproposed, -> { where(proposed_action: nil) }

  validates :approved_tier, inclusion: { in: %w[good great] }, allow_nil: true
  validates :proposed_action, inclusion: { in: %w[approve reject] }, allow_nil: true
  validates :proposed_tier, inclusion: { in: %w[good great] }, allow_nil: true
  validates :review_checklist, inclusion: { in: ELIGIBILITY_CHECKS }
  validates :internal_notes, :extra_links, length: { maximum: 5_000 }

  validates :url, presence: true

  def status
    return :approved if approved_at?
    return :rejected if rejected_at?

    :pending
  end

  def eligibility_confirmed?
    (ELIGIBILITY_CHECKS - review_checklist).empty?
  end

  # The platform to preselect for the reviewer: what was recorded, otherwise
  # a guess from the first evidence link.
  def suggested_platform
    return platform if Virality::Evidence::THRESHOLDS.key?(platform)

    Virality::Evidence.platform_for(evidence_urls.first)
  end

  def evidence_urls
    "#{url} #{extra_links}".split(/[\s,]+/).filter_map do |value|
      uri = URI.parse(value)
      value if uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      nil
    end
  end

  # Saves reviewer-only working state (notes, checklist, extra links, hold).
  # Refused while a decision is scheduled, because the decision is pinned to
  # the mention as it was reviewed.
  def triage!(attributes)
    project.with_lock do
      raise ArgumentError, "Stop the scheduled decision before editing this mention" if virality_decisions.scheduled.exists?

      self.paper_trail_event = "virality_triage"
      update!(attributes)
    end
  end
end
