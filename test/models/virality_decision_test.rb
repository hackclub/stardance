require "test_helper"

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
class ViralityDecisionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @mention = project_mentions(:virality_pending)
    @project = @mention.project
    @project.update!(ship_status: "approved")
    @owner = users(:one)
    @project.memberships.find_by!(user: @owner).update!(role: :owner)
    @admin = users(:two)
    @admin.update!(granted_roles: [ "admin" ])
  end

  test "approval waits thirty seconds and duplicate jobs cannot pay twice" do
    decision = schedule
    assert_equal "scheduled", decision.status
    assert_in_delta 30, decision.process_at - Time.current, 1
    refute decision.process!
    assert_equal :pending, @mention.reload.status
    assert_equal 0, paid

    travel_to decision.process_at + 1.second do
      assert decision.process!
      refute decision.process!
    end
    assert_equal 50, paid
    assert_equal "good", @mention.reload.approved_tier
    assert @owner.reload.achievements.exists?(achievement_slug: "viral_good")
    assert_equal 0, LedgerEntry.joins("INNER JOIN user_achievements ON user_achievements.id = ledger_entries.ledgerable_id")
      .where(ledgerable_type: "User::Achievement", user_achievements: { achievement_slug: "viral_good" }).sum(:amount)
  end

  test "a stopped decision is inert even if its job runs" do
    decision = schedule
    decision.cancel!(actor: @admin)
    travel_to decision.process_at + 1.second do
      ProcessViralityDecisionJob.perform_now(decision.id)
    end
    assert_equal "cancelled", decision.reload.status
    assert_equal 0, paid
    assert_equal :pending, @mention.reload.status
  end

  test "reject and reverse require reasons and rejection has no financial effect" do
    assert_raises(ActiveRecord::RecordInvalid) { schedule(action: "reject", reason: "") }
    decision = schedule(action: "reject", reason: "This is the project, not evidence of reach")
    travel_to(decision.process_at + 1.second) { decision.process! }
    assert_equal :rejected, @mention.reload.status
    assert_equal 0, paid
    reversal = schedule(action: "reverse", reason: "Evidence was overlooked")
    travel_to(reversal.process_at + 1.second) { reversal.process! }
    assert_equal :pending, @mention.reload.status
  end

  test "reversing approval offsets the ledger instead of deleting the credit" do
    decision = schedule
    travel_to(decision.process_at + 1.second) { decision.process! }
    reversal = schedule(action: "reverse", reason: "Engagement was purchased")
    assert_equal 50, paid
    travel_to(reversal.process_at + 1.second) { reversal.process! }
    assert_equal 0, paid
    assert_equal [ 50, -50 ], entries.order(:id).pluck(:amount)
    refute @owner.reload.achievements.exists?(achievement_slug: "viral_good")
  end

  test "another approved mention preserves the bonus on reversal" do
    decision = schedule
    travel_to(decision.process_at + 1.second) { decision.process! }
    second = project_mentions(:virality_second)
    second.update!(approved_at: Time.current, approved_tier: "good")
    reversal = schedule(action: "reverse", reason: "One link is invalid")
    travel_to(reversal.process_at + 1.second) { reversal.process! }
    assert_equal 50, paid
    assert @owner.reload.achievements.exists?(achievement_slug: "viral_good")
  end

  test "permissions are checked again when the job runs" do
    decision = schedule
    @admin.update!(granted_roles: [])
    travel_to(decision.process_at + 1.second) { decision.process! }
    assert_equal "failed", decision.reload.status
    assert_equal :pending, @mention.reload.status
    assert_equal 0, paid
  end

  test "duplicate scheduled decisions are rejected" do
    schedule
    assert_raises(ArgumentError) { schedule }
  end

  test "evidence must meet the tier and eligibility must be confirmed" do
    assert_raises(ActiveRecord::RecordInvalid) { schedule(tier: "great") }
    assert_raises(ActiveRecord::RecordInvalid) { schedule(evidence: evidence.merge("eligibility_confirmed" => "0")) }
    assert_raises(ActiveRecord::RecordInvalid) { schedule(evidence: evidence.merge("metric_value" => "-1")) }
    assert_raises(ActiveRecord::RecordInvalid) { schedule(evidence: evidence.merge("metric_value" => "25.9")) }
  end

  test "an explained manual exception allows an unlisted platform" do
    decision = schedule(reason: "Verified third-party press feature", evidence: evidence.merge("platform" => "Other", "manual_override" => "1"))
    travel_to(decision.process_at + 1.second) { decision.process! }
    assert_equal 50, paid
  end

  test "unapproved projects cannot be approved for virality" do
    @project.update!(ship_status: "submitted")
    assert_raises(ArgumentError) { schedule }
  end

  test "a stale submission fails without payout" do
    decision = schedule
    @mention.update!(url: "https://example.com/changed")
    travel_to(decision.process_at + 1.second) { decision.process! }
    assert_equal "failed", decision.reload.status
    assert_equal 0, paid
  end

  test "processing rolls back the decision when ledger creation fails" do
    decision = schedule
    LedgerEntry.stub(:create!, ->(**) { raise ActiveRecord::RecordInvalid.new(LedgerEntry.new) }) do
      travel_to(decision.process_at + 1.second) { decision.process! }
    end
    assert_equal :pending, @mention.reload.status
    assert_equal "failed", decision.reload.status
    assert_equal 0, paid
  end

  private

  def evidence
    { "platform" => "GitHub", "metric_name" => "stars", "metric_value" => "25", "eligibility_confirmed" => "1" }
  end

  def schedule(**overrides)
    attributes = { action: "approve", tier: "good", reason: "Checked the public repository", evidence: evidence }.merge(overrides)
    ViralityDecision.schedule!(mention: @mention, reviewer: @admin, attributes: attributes)
  end

  def entries
    LedgerEntry.where(ledgerable: @project, created_by: Virality::ReconcileBonus::CREATED_BY)
  end

  def paid = entries.sum(:amount)
end
