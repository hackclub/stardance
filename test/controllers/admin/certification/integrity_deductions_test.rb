require "test_helper"

# Taking stardust back off a shipper for hours a fraud reviewer judged bad. The
# rate is the ship's own: what it actually paid per hour, blessing included.
class Admin::Certification::IntegrityDeductionsTest < ActionDispatch::IntegrationTest
  include UserFactory

  TURBO_STREAM = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  setup do
    @admin = create_user(slack_id: "U_DEDUCT_ADMIN", display_name: "deductadmin")
    @admin.grant_role!(:admin)

    @shipper = create_user(slack_id: "U_DEDUCT_SHIPPER", display_name: "deductshipper")
    @project = Project.create!(title: "Moon lander")
    Project::Membership.create!(project: @project, user: @shipper, role: :owner)
    @ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: @project, user: @shipper, postable: @ship_event)
    @review = ::Certification::Integrity.create!(ship_event: @ship_event, status: :pending)

    sign_in @admin
  end

  test "a paid ship is deducted at the rate it actually paid" do
    paid_out(payout: 240, hours: 10) # 24 stardust an hour

    post admin_certification_integrity_review_deductions_path(@review),
         params: { hours: 2.5, reason: "Heartbeats from a second machine" }

    assert_redirected_to admin_certification_integrity_review_path(@review)
    assert_equal(-60, @shipper.ledger_entries.sole.amount)
    assert_equal(-60, @shipper.balance)
  end

  test "a blessed payout is clawed back at the blessed rate" do
    # 1.2x of a 20/hr curve: the shipper got 24 an hour, so that is what goes back.
    paid_out(payout: 288, hours: 12)

    post admin_certification_integrity_review_deductions_path(@review),
         params: { hours: 1, reason: "Padded hours" }

    assert_equal(-24, @shipper.ledger_entries.sole.amount)
  end

  test "a ship that has not paid out falls back to the flat rate" do
    post admin_certification_integrity_review_deductions_path(@review),
         params: { hours: 3, reason: "AI-written commits" }

    assert_equal(-30, @shipper.ledger_entries.sole.amount)
    assert_equal ::Certification::Integrity::UNPAID_DEDUCTION_RATE, @review.deduction_rate_per_hour
  end

  test "the ledger entry names the project, the hours and the reviewer's reason" do
    post admin_certification_integrity_review_deductions_path(@review),
         params: { hours: 1.5, reason: "Hackatime time on someone else's repo" }

    entry = @shipper.ledger_entries.sole
    assert_equal "Integrity deduction on Moon lander (1.5 hrs): Hackatime time on someone else's repo", entry.reason
    assert_equal "deductadmin (#{@admin.id})", entry.created_by
    assert_equal @shipper, entry.ledgerable, "a User ledgerable is what files the balance change in the audit log"
  end

  test "the deduction is filed against the shipper in the audit log" do
    post admin_certification_integrity_review_deductions_path(@review),
         params: { hours: 1, reason: "Duplicated devlogs" }

    version = PaperTrail::Version.where(item_type: "User", item_id: @shipper.id, event: "balance_adjustment").sole
    assert_equal @admin.id.to_s, version.whodunnit
  end

  test "hours and a reason are both required" do
    post admin_certification_integrity_review_deductions_path(@review), params: { hours: 0, reason: "Nothing" }
    assert_equal "Hours must be more than zero.", flash[:alert]

    post admin_certification_integrity_review_deductions_path(@review), params: { hours: 2, reason: " " }
    assert_equal "A reason is required.", flash[:alert]

    assert_empty @shipper.ledger_entries
  end

  test "hours too small to cost a single stardust are refused" do
    post admin_certification_integrity_review_deductions_path(@review),
         params: { hours: 0.01, reason: "Rounding" }

    assert_equal "That comes to no stardust at this rate.", flash[:alert]
    assert_empty @shipper.ledger_entries
  end

  test "a reviewer who cannot move balances cannot deduct" do
    lead = create_user(slack_id: "U_DEDUCT_LEAD", display_name: "deductlead")
    lead.grant_role!(:fraud_lead)
    sign_in lead

    post admin_certification_integrity_review_deductions_path(@review),
         params: { hours: 1, reason: "Not mine to make" }

    assert_response :forbidden
    assert_empty @shipper.ledger_entries
  end

  test "from the fraud page the check and the balance panel are re-rendered" do
    post admin_certification_integrity_review_deductions_path(@review),
         params: { hours: 2, reason: "Cursor timestamps", fraud_subject_id: @shipper.id }, headers: TURBO_STREAM

    assert_response :success
    assert_equal(-20, @shipper.ledger_entries.sole.amount)
    assert_match ActionView::RecordIdentifier.dom_id(@review), response.body
    assert_match "fraud-subject-identity-panel", response.body
    assert_match "Deducted 20 stardust from deductshipper.", response.body
    assert_predicate @review.reload, :pending?, "a clawback is not a verdict on the check"
  end

  test "the tool is offered on both the review page and the fraud subject page" do
    Certification::Ysws.create!(user: @shipper, project: @project, post_ship_event: @ship_event,
                                original_minutes: 60, reviewed_at: Time.current)

    get admin_certification_integrity_review_path(@review)
    assert_select "form[action=?]", admin_certification_integrity_review_deductions_path(@review)

    get admin_fraud_subject_path(@shipper)
    assert_select "form[action=?]", admin_certification_integrity_review_deductions_path(@review)
  end

  private

  def paid_out(payout:, hours:)
    @ship_event.update_columns(payout: payout, hours_at_payout: hours)
  end
end
