require "test_helper"

# The `undo` endpoints on the funding-request and ship controllers. HCB is
# stubbed throughout - undoing a funding approval cancels a real card grant.
class Admin::Certification::HardwareReviewUndoTest < ActionDispatch::IntegrationTest
  def unspent_grant(amount_cents: 6_000)
    Hashie::Mash.new("id" => "cdg_test", "status" => "active",
                     "amount_cents" => amount_cents, "balance_cents" => amount_cents, "disbursements" => [])
  end

  def spent_grant(amount_cents: 6_000, balance_cents: 500)
    Hashie::Mash.new("id" => "cdg_test", "status" => "active",
                     "amount_cents" => amount_cents, "balance_cents" => balance_cents,
                     "disbursements" => [ { "transaction_id" => "txn_1" } ])
  end

  setup do
    Flipper.enable(:hardware_flow)
    Flipper.enable(:hardware_review_undo)
    @reviewer = create_user(slack_id: "U_UNDO_C_REV", display_name: "undo-c-rev")
    @reviewer.grant_role!(:admin)
    @owner = create_user(slack_id: "U_UNDO_C_OWNER", display_name: "undo-c-owner", verified: true)

    @project = Project.create!(title: "Undo C #{SecureRandom.hex(3)}", hardware_stage: "design")
    @project.memberships.create!(user: @owner, role: :owner)
    add_devlog(@project, "design")
    @funding = approved_funding_with_grant

    sign_in @reviewer
  end

  teardown do
    Flipper.disable(:hardware_flow)
    Flipper.disable(:hardware_review_undo)
  end

  test "a reviewer undoes an approved funding request" do
    HCBService.stub(:show_card_grant, unspent_grant) do
      HCBService.stub(:cancel_card_grant!, ->(hashid:) { { "status" => "canceled" } }) do
        post undo_admin_certification_funding_request_path(@funding)
      end
    end

    assert_redirected_to admin_certification_hardware_review_path(@project)
    assert @funding.reload.pending?
    assert_equal "design", @project.reload.hardware_stage
    assert_nil @funding.hcb_grant_hashid
  end

  test "undoing a spent grant is refused with the blocker as the alert" do
    HCBService.stub(:show_card_grant, spent_grant) do
      post undo_admin_certification_funding_request_path(@funding)
    end

    assert_redirected_to admin_certification_hardware_review_path(@project)
    assert_match(/spent/i, flash[:alert])
    assert @funding.reload.approved?, "a blocked undo leaves the verdict intact"
    assert_equal "build", @project.reload.hardware_stage
  end

  test "a reviewer cannot undo a review on their own project" do
    @project.memberships.create!(user: @reviewer, role: :contributor)

    post undo_admin_certification_funding_request_path(@funding)

    assert_response :forbidden
    assert @funding.reload.approved?
  end

  test "a non-reviewer cannot undo" do
    sign_in @owner

    post undo_admin_certification_funding_request_path(@funding)

    assert_response :forbidden
    assert @funding.reload.approved?
  end

  test "a reviewer cannot undo a review another reviewer decided" do
    certifier = create_user(slack_id: "U_UNDO_CERT", display_name: "undo-certifier")
    certifier.grant_role!(:project_certifier)
    sign_in certifier

    # @funding was decided by @reviewer, so to this reviewer the control is hidden...
    HCBService.stub(:show_card_grant, unspent_grant) do
      get admin_certification_hardware_review_path(@project)
    end
    assert_response :success
    assert_select ".review-undo__trigger", 0

    # ...and the action itself is forbidden.
    post undo_admin_certification_funding_request_path(@funding)
    assert_response :forbidden
    assert @funding.reload.approved?
  end

  test "a reviewer undoes their own funding review" do
    certifier = create_user(slack_id: "U_UNDO_OWN_FR", display_name: "undo-own-fr")
    certifier.grant_role!(:project_certifier)
    @funding.update_columns(reviewer_id: certifier.id)
    sign_in certifier

    HCBService.stub(:show_card_grant, unspent_grant) do
      HCBService.stub(:cancel_card_grant!, ->(hashid:) { { "status" => "canceled" } }) do
        post undo_admin_certification_funding_request_path(@funding)
      end
    end

    assert_redirected_to admin_certification_hardware_review_path(@project)
    assert @funding.reload.pending?, "the reviewer's own verdict is reversed"
  end

  test "a reviewer sees the undo control on a review they decided" do
    certifier = create_user(slack_id: "U_UNDO_OWN_VIEW", display_name: "undo-own-view")
    certifier.grant_role!(:project_certifier)
    @funding.update_columns(reviewer_id: certifier.id)
    sign_in certifier

    HCBService.stub(:show_card_grant, unspent_grant) do
      get admin_certification_hardware_review_path(@project)
    end

    assert_response :success
    assert_select ".review-undo__trigger", text: /Undo review/
  end

  test "a reviewer undoes their own ship certification" do
    certifier = create_user(slack_id: "U_UNDO_OWN_SHIP", display_name: "undo-own-ship")
    certifier.grant_role!(:project_certifier)
    project = Project.create!(title: "Undo Own Ship #{SecureRandom.hex(3)}", hardware_stage: "build")
    project.memberships.create!(user: @owner, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true, hours_at_ship: 4)
    Post.create!(project: project, user: @owner, postable: ship_event)
    project.update_columns(ship_status: "submitted", shipped_at: Time.current)
    cert = project.ship_reviews.create!(status: :pending, post_ship_event: ship_event)
    cert.update!(status: :approved, reviewer: certifier)
    sign_in certifier

    post undo_admin_certification_ship_path(cert)

    assert_redirected_to admin_certification_hardware_review_path(project)
    assert cert.reload.withdrawn?, "the reviewer's own ship verdict is withdrawn"
  end

  test "a reviewer undoes an approved ship certification" do
    project = Project.create!(title: "Undo Ship #{SecureRandom.hex(3)}", hardware_stage: "build")
    project.memberships.create!(user: @owner, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true, hours_at_ship: 4)
    Post.create!(project: project, user: @owner, postable: ship_event)
    project.update_columns(ship_status: "submitted", shipped_at: Time.current)
    cert = project.ship_reviews.create!(status: :pending, post_ship_event: ship_event)
    cert.update!(status: :approved, reviewer: @reviewer)

    post undo_admin_certification_ship_path(cert)

    assert_redirected_to admin_certification_hardware_review_path(project)
    assert cert.reload.withdrawn?, "the undone ship review is withdrawn, not left pending"
    assert_equal "pending", ship_event.reload.certification_status
    assert_equal "draft", project.reload.ship_status, "the project is un-submitted, not auto-queued"
    assert_not project.reload.awaiting_ship_review?, "no pending review remains to block a manual re-ship"
  end

  test "the review page offers an undo control for the latest decided review" do
    HCBService.stub(:show_card_grant, unspent_grant) do
      get admin_certification_hardware_review_path(@project)
    end

    assert_response :success
    assert_select ".review-undo__trigger", text: /Undo review/
    # The trigger carries the orange dashed admin-tool marker.
    assert_select ".tools-do .review-undo__trigger"
    assert_select ".review-undo__group-label", text: /Things this will do/
    assert_select ".review-undo__confirm-form button", text: /Undo review/
  end

  test "a spent grant disables the undo confirm and shows the blocker" do
    HCBService.stub(:show_card_grant, spent_grant) do
      get admin_certification_hardware_review_path(@project)
    end

    assert_response :success
    assert_select ".review-undo__row--block", text: /spent/i
    assert_select ".review-undo__confirm-form", count: 0
    assert_select "button[disabled]", text: /Undo review/
  end

  test "an undone funding review stays in the history with a Reversed badge" do
    HCBService.stub(:show_card_grant, unspent_grant) do
      HCBService.stub(:cancel_card_grant!, ->(hashid:) { { "status" => "canceled" } }) do
        post undo_admin_certification_funding_request_path(@funding)
      end
    end
    assert @funding.reload.reversed_at.present?

    get admin_certification_hardware_review_path(@project)

    assert_response :success
    assert_select ".hardware-review__history .status-pill--reversed", text: /Reversed/
  end

  private

  def add_devlog(project, phase)
    devlog = Post::Devlog.new(body: "log", duration_seconds: 3600, phase: phase)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: @owner, postable: devlog)
  end

  def approved_funding_with_grant
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 3, requested_amount_cents: 6_000, status: :pending
    )
    HCBService.stub(:create_card_grant, { "id" => "cdg_test" }) do
      fr.update!(reviewer: @reviewer, status: :approved, feedback: "great")
    end
    fr.reload
  end
end
