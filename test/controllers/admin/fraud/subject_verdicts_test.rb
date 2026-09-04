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

    assert_redirected_to admin_certification_integrity_reviews_path
    assert_predicate check.reload, :pending?
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

  test "putting an order on hold keeps it in the queue and re-renders the row" do
    order = pending_order

    post place_on_hold_admin_shop_order_path(order),
         params: { fraud_subject_id: @subject.id }, headers: TURBO_STREAM

    assert_response :success
    assert_equal "on_hold", order.reload.aasm_state
    assert_match "Release hold", response.body
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

  def pending_integrity_check
    project = Project.create!(title: "Shipped #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: @subject, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: @subject, postable: ship_event)
    Certification::Integrity.create!(ship_event: ship_event, status: :pending)
  end
end
