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
#  hcb_grant_hashid          :string
#  internal_reason           :text
#  lock_version              :integer          default(0), not null
#  prizes_waived             :boolean          default(FALSE), not null
#  requested_amount_cents    :integer          not null
#  stardust_earned           :integer
#  status                    :integer          default(0), not null
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
  HCB_GRANT_RESPONSE = { "id" => "test_grant_123" }.freeze

  def setup
    Flipper.enable(:hardware_flow)
    @owner = User.create!(
      email: "owner-#{SecureRandom.hex(6)}@example.com",
      display_name: "Owner#{SecureRandom.hex(3)}",
      slack_id: "U#{SecureRandom.hex(8)}",
      verification_status: :verified, ysws_eligible: true
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

  test "available_for holds back projects with an unresolved fraud report" do
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 3_000, status: :pending
    )
    assert_includes ::Certification::FundingRequest.available_for(@reviewer), fr

    report = @project.reports.create!(
      reporter: @reviewer, reason: "fraud", status: :pending,
      details: "Looks like a resold kit, not a real build."
    )
    assert_not_includes ::Certification::FundingRequest.available_for(@reviewer), fr,
      "a project with a pending fraud report should be held back from the review queue"

    report.update!(status: :dismissed)
    assert_includes ::Certification::FundingRequest.available_for(@reviewer), fr,
      "clearing the fraud report should return the project to the queue"
  end

  test "rejects a requested amount above the tier maximum" do
    fr = @project.certification_funding_requests.new(user: @owner, complexity_tier: 1, requested_amount_cents: 5_000)
    assert_not fr.valid?
    assert fr.errors[:requested_amount_cents].any?
  end

  test "approval switches the project to build and issues the HCB grant" do
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 3, requested_amount_cents: 6_000, status: :pending
    )
    HCBService.stub(:create_card_grant, HCB_GRANT_RESPONSE) do
      fr.update!(reviewer: @reviewer, status: :approved)
    end

    assert_equal "build", @project.reload.hardware_stage
    assert_equal Certification::FundingRequest::REVIEW_BOUNTY, fr.reload.stardust_earned
    assert_equal "test_grant_123", fr.reload.hcb_grant_hashid
  end

  test "returned requests leave the project untouched" do
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 3_000, status: :pending
    )
    fr.update!(reviewer: @reviewer, status: :returned, feedback: "needs more detail")

    assert_equal "design", @project.reload.hardware_stage
  end

  test "a funded project must post a build devlog before it can ship" do
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 3, requested_amount_cents: 6_000, status: :pending
    )
    HCBService.stub(:create_card_grant, HCB_GRANT_RESPONSE) do
      fr.update!(reviewer: @reviewer, status: :approved)
    end
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

  test "kit mission: funding request needs no tier or amount" do
    attach_kit_mission
    fr = @project.certification_funding_requests.new(user: @owner)
    assert fr.valid?, fr.errors.full_messages.to_sentence
    assert fr.save
    assert_equal Certification::FundingRequest::TIER_MAX_CENTS.keys.min, fr.complexity_tier
    assert_equal 0, fr.requested_amount_cents
    assert fr.awards_design_kit?
  end

  test "kit mission: approval delivers a kit instead of a cash grant" do
    attach_kit_mission
    fr = @project.certification_funding_requests.create!(user: @owner, status: :pending)

    grant_called = false
    HCBService.stub(:create_card_grant, ->(*) { grant_called = true; HCB_GRANT_RESPONSE }) do
      fr.update!(reviewer: @reviewer, status: :approved)
    end

    assert_not grant_called, "kit mission should not issue an HCB grant"
    assert_nil fr.reload.hcb_grant_hashid
    assert_equal "build", @project.reload.hardware_stage
    assert_equal true, fr.notification_locals[:awards_kit]
  end

  test "approving without a grant advances the project but issues no grant" do
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 3, requested_amount_cents: 6_000, status: :pending
    )

    grant_called = false
    HCBService.stub(:create_card_grant, ->(*) { grant_called = true; HCB_GRANT_RESPONSE }) do
      fr.update!(reviewer: @reviewer, verdict: "approved_without_grant", approved_amount_dollars: 60)
    end

    assert_not grant_called, "approving without a grant should not issue an HCB grant"
    fr.reload
    assert fr.approved?
    assert fr.approved_without_grant?
    assert_not fr.issues_grant?
    assert_equal 0, fr.approved_amount_cents, "the submitted amount is ignored"
    assert_nil fr.hcb_grant_hashid
    assert_equal "build", @project.reload.hardware_stage
    assert_equal Certification::FundingRequest::REVIEW_BOUNTY, fr.stardust_earned
  end

  test "the verdict reader reflects how an approval was funded" do
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 3_000, status: :pending
    )
    assert_nil fr.verdict

    HCBService.stub(:create_card_grant, HCB_GRANT_RESPONSE) do
      fr.update!(reviewer: @reviewer, status: :approved)
    end

    assert_equal "approved", Certification::FundingRequest.find(fr.id).verdict
  end

  test "approving a superseded funding request does not advance the project or issue a grant" do
    old = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 3_000, status: :pending
    )
    old.update!(reviewer: @reviewer, status: :returned, feedback: "needs work")
    # Resubmit: a newer request supersedes the returned one.
    newer = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 3_000, status: :pending
    )

    assert_not old.latest_for_project?
    assert newer.latest_for_project?

    HCBService.stub(:create_card_grant, HCB_GRANT_RESPONSE) do
      old.update!(reviewer: @reviewer, status: :approved)
    end

    assert_equal "design", @project.reload.hardware_stage, "a superseded request must not advance the project"
    assert_nil old.reload.hcb_grant_hashid, "a superseded request must not issue a grant"
  end

  private

  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  def attach_kit_mission
    mission = create_mission
    mission.update!(hardware: true)
    kit = ShopItem.new(name: "Hackpad Kit #{SecureRandom.hex(3)}", description: "The kit for this mission",
                       ticket_cost: 0, type: "ShopItem::ThirdPartyPhysical", enabled: true, mission_prize_only: true)
    kit.image.attach(io: StringIO.new(PIXEL_PNG), filename: "kit.png", content_type: "image/png")
    kit.save!
    mission.prizes.create!(shop_item: kit, position: 0, category: :after_design)
    @project.mission_attachments.create!(mission: mission)
    mission
  end

  def create_devlog(phase:)
    devlog = Post::Devlog.new(body: "work log", duration_seconds: 3600, phase: phase)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: @project, user: @owner, postable: devlog)
  end
end
