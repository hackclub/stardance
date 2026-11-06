# == Schema Information
#
# Table name: virality_decisions
#
#  id                 :bigint           not null, primary key
#  action             :string           not null
#  cancelled_at       :datetime
#  error_message      :text
#  evidence           :jsonb            not null
#  process_at         :datetime         not null
#  processed_at       :datetime
#  reason             :text
#  result             :jsonb            not null
#  status             :string           default("scheduled"), not null
#  tier               :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  cancelled_by_id    :bigint
#  project_mention_id :bigint           not null
#  reviewer_id        :bigint           not null
#
# Indexes
#
#  due_virality_decisions                          (process_at) WHERE ((status)::text = 'scheduled'::text)
#  index_virality_decisions_on_cancelled_by_id     (cancelled_by_id)
#  index_virality_decisions_on_project_mention_id  (project_mention_id)
#  index_virality_decisions_on_reviewer_id         (reviewer_id)
#  one_scheduled_virality_decision_per_mention     (project_mention_id) UNIQUE WHERE ((status)::text = 'scheduled'::text)
#
# Foreign Keys
#
#  fk_rails_...  (cancelled_by_id => users.id)
#  fk_rails_...  (project_mention_id => project_mentions.id)
#  fk_rails_...  (reviewer_id => users.id)
#
class ViralityDecision < ApplicationRecord
  DELAY = 30.seconds
  ACTIONS = %w[approve reject reverse].freeze
  STATUSES = %w[scheduled cancelled processed failed].freeze

  has_paper_trail
  belongs_to :project_mention
  belongs_to :reviewer, class_name: "User"
  belongs_to :cancelled_by, class_name: "User", optional: true

  scope :scheduled, -> { where(status: "scheduled") }
  scope :due, -> { scheduled.where(process_at: ..Time.current) }

  validates :action, inclusion: { in: ACTIONS }
  validates :status, inclusion: { in: STATUSES }
  validates :process_at, presence: true
  validates :reason, length: { maximum: 2_000 }
  validates :reason, presence: true, if: -> { action.in?(%w[reject reverse]) || evidence["manual_override"] == "1" }
  validates :tier, inclusion: { in: %w[good great] }, if: -> { action == "approve" }
  validate :approval_evidence, on: :create

  after_create_commit :enqueue_processing

  def self.reviewer?(user)
    user.present? && (user.has_role?(:admin) || user.has_role?(:super_admin))
  end

  def self.schedule!(mention:, reviewer:, attributes:)
    raise ArgumentError, "Only admins can review viral mentions" unless reviewer?(reviewer)

    mention.project.with_lock do
      mention.reload
      raise ArgumentError, "A decision is already scheduled for this mention" if mention.virality_decisions.scheduled.exists?

      decision = mention.virality_decisions.build(attributes)
      decision.reviewer = reviewer
      decision.status = "scheduled"
      decision.process_at = DELAY.from_now
      decision.evidence = decision.evidence.merge("mention_updated_at" => mention.updated_at.iso8601(6))
      decision.check_state!
      decision.validate!
      decision.result = decision.preview
      decision.save!
      decision
    end
  end

  def cancel!(actor:)
    raise ArgumentError, "Only admins can stop decisions" unless self.class.reviewer?(actor)

    project_mention.project.with_lock do
      with_lock do
        raise ArgumentError, "This decision has already finished" unless status == "scheduled"

        PaperTrail.request(whodunnit: actor.id.to_s) do
          self.paper_trail_event = "virality_cancelled"
          update!(status: "cancelled", cancelled_by: actor, cancelled_at: Time.current)
        end
      end
    end
  end

  def process!
    project_mention.project.with_lock do
      with_lock do
        return false unless status == "scheduled" && process_at <= Time.current

        PaperTrail.request(whodunnit: reviewer_id.to_s) do
          raise ArgumentError, "The reviewing admin no longer has permission" unless self.class.reviewer?(reviewer.reload)
          project_mention.reload
          check_state!
          raise ArgumentError, "The submission changed. Review it again." unless evidence["mention_updated_at"] == project_mention.updated_at.iso8601(6)
          raise ArgumentError, "Payout amounts changed. Review the new preview." unless preview["changes"] == result["changes"]

          project_mention.paper_trail_event = "virality_#{action}"
          project_mention.update!(mention_changes)
          reconciliation = Virality::ReconcileBonus.new(project_mention.project).call
          self.paper_trail_event = "virality_processed"
          update!(status: "processed", processed_at: Time.current, result: reconciliation)
        end
        true
      end
    end
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    fail!(error.message)
    false
  end

  def fail!(message)
    reload
    with_lock do
      return unless status == "scheduled"

      PaperTrail.request(whodunnit: reviewer_id.to_s) do
        self.paper_trail_event = "virality_failed"
        update!(status: "failed", error_message: message.truncate(2_000))
      end
    end
  end

  def preview
    service = Virality::ReconcileBonus.new(project_mention.project)
    proposed_tier = service.tier(excluding: project_mention, adding: action == "approve" ? tier : nil)
    service.preview(tier: proposed_tier).deep_stringify_keys
  end

  def check_state!
    if action == "reverse"
      raise ArgumentError, "There is no decision to reverse" if project_mention.status == :pending
    else
      raise ArgumentError, "Reverse the previous decision before reviewing again" unless project_mention.status == :pending
    end
    if action == "approve"
      raise ArgumentError, "The project must be approved first" unless project_mention.project.ship_status == "approved"
    end
  end

  private

  def enqueue_processing
    ProcessViralityDecisionJob.set(wait_until: process_at).perform_later(id)
  end

  def approval_evidence
    return unless action == "approve"

    unless evidence["eligibility_confirmed"] == "1"
      errors.add(:base, "Confirm originality, Hack Club credit, and organic reach before approving")
    end
    return if evidence["manual_override"] == "1" && reason.present?

    value = Integer(evidence["metric_value"], exception: false)
    unless value && value >= 0 && Virality::Evidence.qualifies?(
      platform: evidence["platform"], metric_name: evidence["metric_name"], metric_value: value, tier: tier
    )
      errors.add(:base, "The verified metric must meet the selected tier, or explain a manual exception")
    end
  end

  def mention_changes
    common = { reviewer: reviewer, reviewer_notes: reason }
    case action
    when "approve"
      common.merge(approved_at: Time.current, rejected_at: nil, approved_tier: tier,
        platform: evidence["platform"], metric_name: evidence["metric_name"], metric_value: evidence["metric_value"].presence)
    when "reject"
      common.merge(approved_at: nil, rejected_at: Time.current, approved_tier: nil)
    when "reverse"
      common.merge(approved_at: nil, rejected_at: nil, approved_tier: nil)
    end
  end
end
