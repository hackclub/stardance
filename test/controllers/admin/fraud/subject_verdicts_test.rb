require "test_helper"

# Verdicts submitted from the per-person fraud page settle the item and answer
# with a swap, so the reviewer stays on the person instead of being sent back to
# whichever queue the item came from.
class Admin::Fraud::SubjectVerdictsTest < ActionDispatch::IntegrationTest
  include UserFactory

  TURBO_STREAM = { "Accept" => "text/vnd.turbo-stream.html" }.freeze
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @admin = create_user(slack_id: "U_FRAUD_VERDICT_ADMIN", display_name: "verdictadmin")
    @admin.grant_role!(:admin)

    @subject = create_user(slack_id: "U_FRAUD_VERDICT_SUBJECT", display_name: "verdictsubject")
    @reporter = create_user(slack_id: "U_FRAUD_VERDICT_REPORTER", display_name: "verdictreporter")

    sign_in @admin
  end

  test "resolving a flag swaps the item out instead of redirecting" do
    flag = flag_a_project

    post review_admin_certification_report_path(flag),
         params: { fraud_subject_id: @subject.id }, headers: TURBO_STREAM

    assert_response :success
    assert_predicate flag.reload, :reviewed?
    assert_match "turbo-stream", response.media_type
    assert_match ActionView::RecordIdentifier.dom_id(flag), response.body
  end

  test "a verdict fills the item's slot in the progress bar" do
    flag = flag_a_project

    post review_admin_certification_report_path(flag),
         params: { fraud_subject_id: @subject.id }, headers: TURBO_STREAM

    assert_response :success
    assert_match ActionView::RecordIdentifier.dom_id(flag, :progress), response.body
    assert_match "fraud-subject__progress-slot--done", response.body
    assert_match "fraud-subject__progress-slot--flag", response.body
  end

  test "a dismissed flag keeps the colour of the queue it came from" do
    flag = flag_a_project

    post dismiss_admin_certification_report_path(flag),
         params: { fraud_subject_id: @subject.id }, headers: TURBO_STREAM

    assert_response :success
    assert_predicate flag.reload, :dismissed?
    assert_match "fraud-subject__progress-slot--flag", response.body
    assert_no_match "progress-slot--cleared", response.body
    assert_match "fraud-subject__item--flag", response.body
  end

  test "a verdict accrues a payout tally and shows the multiplier" do
    flag = flag_a_project
    pending_integrity_check

    post review_admin_certification_report_path(flag),
         params: { fraud_subject_id: @subject.id }, headers: TURBO_STREAM

    assert_response :success
    payout = FraudReviewPayout.sole
    assert_equal [ @admin.id, @subject.id, 1 ], [ payout.reviewer_id, payout.subject_id, payout.flag_count ]
    assert_nil payout.completed_at, "a person with a check still waiting is not cleared"
    assert_match "fraud-subject__payout-mult--flag", response.body
    assert_match "1.1", response.body
  end

  test "clearing the last review completes the payout and shows the total" do
    flag = flag_a_project

    post review_admin_certification_report_path(flag),
         params: { fraud_subject_id: @subject.id }, headers: TURBO_STREAM

    assert_response :success
    payout = FraudReviewPayout.sole
    assert_not_nil payout.completed_at
    assert_equal 1, payout.credited_amount
    assert_match "fraud-subject__payout-result--done", response.body
    assert_match "fraud-celebration", response.body
    assert_match "fraud-payout-celebration-total-value", response.body
  end

  test "a payout stays unpayable until the person is cleared" do
    flag_a_project
    flag = flag_a_project
    pending_integrity_check

    post review_admin_certification_report_path(flag),
         params: { fraud_subject_id: @subject.id }, headers: TURBO_STREAM

    assert_response :success
    assert_empty FraudReviewPayout.payable
  end

  test "resolving a flag from its own dashboard still redirects" do
    flag = flag_a_project

    post review_admin_certification_report_path(flag)

    assert_redirected_to admin_certification_reports_path
    assert_predicate flag.reload, :reviewed?
  end

  test "an integrity verdict takes the claim it never opened" do
    check = pending_integrity_check

    patch admin_certification_integrity_review_path(check),
          params: { fraud_subject_id: @subject.id, decision: "pass" }, headers: TURBO_STREAM

    assert_response :success
    assert_predicate check.reload, :manually_passed?
    assert_equal @admin.id, check.reviewer_id
  end

  test "an integrity verdict cannot jump another reviewer's claim" do
    other = create_user(slack_id: "U_FRAUD_OTHER", display_name: "otherreviewer")
    check = pending_integrity_check
    Certification::Integrity.atomic_claim!(check.id, other)

    patch admin_certification_integrity_review_path(check),
          params: { fraud_subject_id: @subject.id, decision: "pass" }, headers: TURBO_STREAM

    # A redirect here would render as "Content missing" inside the check's
    # frame, so the claim guard answers with the frame and the reason instead.
    assert_response :unprocessable_entity
    assert_match ActionView::RecordIdentifier.dom_id(check), response.body
    assert_match "claimed by another admin", response.body
    assert_predicate check.reload, :pending?
  end

  test "deducting with no hours answers with the check, not a missing frame" do
    check = pending_integrity_check

    patch admin_certification_integrity_review_path(check),
          params: { fraud_subject_id: @subject.id, decision: "deduct", deduction_hours: "" },
          headers: TURBO_STREAM

    assert_response :unprocessable_entity
    assert_match ActionView::RecordIdentifier.dom_id(check), response.body
    assert_match "fraud-subject__item-error", response.body
    assert_predicate check.reload, :pending?
    assert_nil check.deduction_minutes
  end

  test "a verdict is refused when another reviewer holds the person" do
    other = create_user(slack_id: "U_FRAUD_HOLDER", display_name: "holder")
    FraudSubjectClaim.claim(@subject, other)
    flag = flag_a_project

    post review_admin_certification_report_path(flag),
         params: { fraud_subject_id: @subject.id }, headers: TURBO_STREAM

    assert_response :conflict
    assert_match "holder", response.body
    assert_match "was not recorded", response.body
    assert_predicate flag.reload, :pending?
    assert_equal 0, FraudReviewPayout.count
  end

  test "a lapsed claim does not block the next reviewer's verdict" do
    other = create_user(slack_id: "U_FRAUD_LAPSED", display_name: "lapsed")
    FraudSubjectClaim.claim(@subject, other)
                     .update!(claimed_at: (FraudSubjectClaim::CLAIM_TTL + 1.minute).ago)
    flag = flag_a_project

    post review_admin_certification_report_path(flag),
         params: { fraud_subject_id: @subject.id }, headers: TURBO_STREAM

    assert_response :success
    assert_predicate flag.reload, :reviewed?
  end

  test "a cascading verdict fills the slots of the checks it settled too" do
    project = Project.create!(title: "Many ships")
    Project::Membership.create!(project: project, user: @subject, role: :owner)
    decided, sibling = 2.times.map { integrity_check_on(project) }

    patch admin_certification_integrity_review_path(decided),
          params: { fraud_subject_id: @subject.id, decision: "pass" }, headers: TURBO_STREAM

    assert_response :success
    assert_predicate sibling.reload, :manually_passed?, "the cascade settled the sibling"
    assert_match ActionView::RecordIdentifier.dom_id(sibling, :progress), response.body
    assert_match "fraud-subject__progress-slot--done", response.body
  end

  test "a non-cascading verdict leaves the other checks' slots alone" do
    project = Project.create!(title: "Deducted ship")
    Project::Membership.create!(project: project, user: @subject, role: :owner)
    decided, sibling = 2.times.map { integrity_check_on(project) }

    patch admin_certification_integrity_review_path(decided),
          params: { fraud_subject_id: @subject.id, decision: "deduct", deduction_hours: "2" },
          headers: TURBO_STREAM

    assert_response :success
    assert_predicate sibling.reload, :pending?
    assert_no_match ActionView::RecordIdentifier.dom_id(sibling, :progress), response.body
  end

  test "a cascading verdict re-renders the whole integrity list" do
    check = pending_integrity_check

    patch admin_certification_integrity_review_path(check),
          params: { fraud_subject_id: @subject.id, decision: "pass" }, headers: TURBO_STREAM

    assert_response :success
    assert_match "fraud-subject-integrity-items", response.body
  end

  test "a deduction replaces only the row it settled" do
    check = pending_integrity_check

    patch admin_certification_integrity_review_path(check),
          params: { fraud_subject_id: @subject.id, decision: "deduct", deduction_hours: "1.5" },
          headers: TURBO_STREAM

    assert_response :success
    assert_predicate check.reload, :deducted?
    assert_equal 90, check.deduction_minutes
    assert_match ActionView::RecordIdentifier.dom_id(check), response.body
  end

  test "an order row shows its fulfillment cost, stardust cost and the buyer's country" do
    order = pending_order
    @subject.update!(geocoded_country: "CA")

    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_select ".fraud-subject__facts" do
      assert_select "dd", text: /\$7\.00/
      assert_select "dd", text: /CA/
    end
  end

  test "the subject page offers bulk order verdicts" do
    pending_order

    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_select "form[action=?] button", bulk_approve_admin_shop_orders_path, text: "Approve all 1 order"
    assert_select "form[action=?] input[type=submit]", bulk_reject_admin_shop_orders_path, value: "Reject all orders"
  end

  test "the subject page shows previously approved orders" do
    order = pending_order
    order.update_columns(aasm_state: "awaiting_periodical_fulfillment", awaiting_periodical_fulfillment_at: Time.current)

    get admin_fraud_subject_path(@subject)

    assert_response :success
    assert_select "#fraud-subject-approved-orders", text: /Previously approved orders/
    assert_match order.shop_item.name, response.body
    assert_match "Awaiting periodical fulfillment", response.body
  end

  test "bulk rejection rejects every selected subject order and audits each verdict" do
    order = pending_order
    project = Project.create!(title: "Fraud source")

    post bulk_reject_admin_shop_orders_path,
         params: {
           order_ids: [ order.id ],
           reason: "Fraud review failed",
           internal_rejection_reason: "Matching evidence",
           fraud_related_project_id: project.id
         },
         headers: { "HTTP_REFERER" => admin_fraud_subject_url(@subject) }

    assert_redirected_to admin_fraud_subject_path(@subject)
    assert_predicate order.reload, :rejected?
    assert PaperTrail::Version.where(item_type: "ShopOrder", item_id: order.id, whodunnit: @admin.id.to_s).exists?
  end

  test "putting an order on hold keeps it in the queue and re-renders the row" do
    order = pending_order

    assert_enqueued_with(job: Shop::ReleaseExpiredOrderHoldsJob) do
      post place_on_hold_admin_shop_order_path(order),
           params: { fraud_subject_id: @subject.id }, headers: TURBO_STREAM
    end

    assert_response :success
    assert_equal "on_hold", order.reload.aasm_state
    assert_match "Release hold", response.body
    assert_match "Automatically releases in", response.body
    assert_select "[data-controller='countdown'][data-countdown-reset-at-value]"
  end

  test "releasing a hold puts the order back to pending" do
    order = pending_order
    order.update_columns(aasm_state: "on_hold")

    post release_from_hold_admin_shop_order_path(order),
         params: { fraud_subject_id: @subject.id }, headers: TURBO_STREAM

    assert_response :success
    assert_equal "pending", order.reload.aasm_state
    assert_no_match "Release hold", response.body
  end

  private

  def pending_order
    @subject.update!(has_gotten_free_stickers: true) # clears the shop-tutorial gate
    order = @subject.shop_orders.create!(shop_item: shop_item, quantity: 1,
                                         frozen_address: { "country" => "US" })
    order.update_columns(aasm_state: "pending")
    order
  end

  def shop_item
    @shop_item ||= begin
      item = ShopItem.new(name: "Verdict patch #{SecureRandom.hex(4)}", description: "Test item",
                          ticket_cost: 0, usd_cost: 7, type: "ShopItem::ThirdPartyPhysical", enabled: true)
      item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
      item.save!
      item
    end
  end

  def flag_a_project
    project = Project.create!(title: "Flagged #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: @subject, role: :owner)
    Project::Report.create!(project: project, reporter: @reporter, reason: "fraud",
                            details: "Detailed enough to pass validation", status: :pending)
  end

  def integrity_check_on(project)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: @subject, postable: ship_event)
    Certification::Integrity.create!(ship_event: ship_event, status: :pending)
  end

  def pending_integrity_check
    project = Project.create!(title: "Shipped #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: @subject, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: @subject, postable: ship_event)
    Certification::Integrity.create!(ship_event: ship_event, status: :pending)
  end
end
