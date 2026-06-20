# == Schema Information
#
# Table name: certification_funding_requests
#
#  id                        :bigint           not null, primary key
#  approved_amount_cents     :integer
#  claim_expires_at          :datetime
#  claimed_at                :datetime
#  complexity_tier           :integer          not null
#  decided_at                :datetime
#  discount_stardust_awarded :integer
#  feedback                  :text
#  internal_reason           :text
#  lock_version              :integer          default(0), not null
#  requested_amount_cents    :integer          not null
#  stardust_earned           :integer
#  status                    :integer          default("pending"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  project_id                :bigint           not null
#  reviewer_id               :bigint
#  user_id                   :bigint           not null
#
# Indexes
#
#  idx_funding_requests_on_status_claim_expires         (status,claim_expires_at)
#  index_certification_funding_requests_on_decided_at   (decided_at)
#  index_certification_funding_requests_on_project_id   (project_id)
#  index_certification_funding_requests_on_reviewer_id  (reviewer_id)
#  index_certification_funding_requests_on_user_id      (user_id)
#  index_funding_requests_unique_pending_project        (project_id) UNIQUE WHERE (status = 0)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (reviewer_id => users.id)
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

class Certification::FundingRequestTest < ActiveSupport::TestCase
  def setup
    Flipper.enable(:hardware_flow)
    @owner = User.create!(
      email: "owner-#{SecureRandom.hex(6)}@example.com",
      display_name: "Owner#{SecureRandom.hex(3)}",
      slack_id: "U#{SecureRandom.hex(8)}"
    )
    @reviewer = User.create!(
      email: "rev-#{SecureRandom.hex(6)}@example.com",
      display_name: "Rev#{SecureRandom.hex(3)}",
      slack_id: "U#{SecureRandom.hex(8)}"
    )
    @project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "design")
    Project::Membership.create!(project: @project, user: @owner, role: :owner)
    devlog = Post::Devlog.new(body: "initial log", duration_seconds: 3600, phase: "design")
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: @project, user: @owner, postable: devlog)
  end

  test "rejects a requested amount above the tier maximum" do
    fr = @project.certification_funding_requests.new(user: @owner, complexity_tier: 1, requested_amount_cents: 5_000)
    assert_not fr.valid?
    assert fr.errors[:requested_amount_cents].any?
  end

  test "approval switches the project to build and accrues the owner discount" do
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 3, requested_amount_cents: 6_000, status: :pending
    )
    fr.update!(reviewer: @reviewer, status: :approved)

    assert_equal "build", @project.reload.hardware_stage
    # tier 3 (S) => flat 100% discount on the 300✦ Outpost Ticket = 300
    assert_equal 300, @owner.reload.outpost_discount_stardust
    assert_equal Certification::FundingRequest::REVIEW_BOUNTY, fr.reload.stardust_earned
  end

  test "approving for less than requested still grants the full flat tier discount" do
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 3, requested_amount_cents: 10_000, status: :pending
    )
    fr.update!(reviewer: @reviewer, status: :approved, approved_amount_dollars: 40)

    # flat per-tier discount: the approved amount no longer affects it; tier 3 (S) = 300
    assert_equal 300, @owner.reload.outpost_discount_stardust
  end

  test "discount accrual is idempotent across re-saves" do
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 3, requested_amount_cents: 6_000, status: :pending
    )
    fr.update!(reviewer: @reviewer, status: :approved)
    assert_equal 300, @owner.reload.outpost_discount_stardust

    fr.update!(feedback: "nice work")
    assert_equal 300, @owner.reload.outpost_discount_stardust
  end

  test "returned requests leave the project and discount untouched" do
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 3_000, status: :pending
    )
    fr.update!(reviewer: @reviewer, status: :returned, feedback: "needs more detail")

    assert_equal "design", @project.reload.hardware_stage
    assert_equal 0, @owner.reload.outpost_discount_stardust
  end

  test "a funded project must post a build devlog before it can ship" do
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 3, requested_amount_cents: 6_000, status: :pending
    )
    fr.update!(reviewer: @reviewer, status: :approved)
    @project.reload

    label = "Post at least one build devlog before shipping"

    assert @project.received_grant?
    assert_not @project.has_build_devlog_since_last_ship?
    assert_includes @project.ship_blocking_errors, label

    # A design-phase devlog does NOT satisfy the gate.
    create_devlog(phase: "design")
    assert_not @project.has_build_devlog_since_last_ship?
    assert_includes @project.ship_blocking_errors, label

    # A build-phase devlog does.
    create_devlog(phase: "build")
    assert @project.has_build_devlog_since_last_ship?
    assert_not_includes @project.ship_blocking_errors, label
  end

  private

  def create_devlog(phase:)
    devlog = Post::Devlog.new(body: "work log", duration_seconds: 3600, phase: phase)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: @project, user: @owner, postable: devlog)
  end
end
