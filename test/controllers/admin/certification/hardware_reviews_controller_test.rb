require "test_helper"

class Admin::Certification::HardwareReviewsControllerTest < ActionDispatch::IntegrationTest
  # Approving a funding request issues a real HCB card grant.
  HCB_GRANT_RESPONSE = { "id" => "test_grant_hwq" }.freeze

  setup do
    Flipper.enable(:hardware_flow)

    @reviewer = create_user(slack_id: "U_HWQ_REV", display_name: "hwq-reviewer")
    @reviewer.grant_role!(:admin)

    @owner = create_user(slack_id: "U_HWQ_OWNER", display_name: "hwq-owner", verified: true)

    @design_project = hardware_project("Design bot", "design")
    # A funding request requires the project to have at least one devlog.
    add_devlog(@design_project)
    @funding = @design_project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 4_200, status: :pending
    )

    @build_project = hardware_project("Build bot", "build")
    @ship = ::Certification::Ship.create!(project: @build_project, status: :pending)

    sign_in @reviewer
  end

  teardown { Flipper.disable(:hardware_flow) }

  test "the design queue lists only funding requests" do
    get design_admin_certification_hardware_reviews_path

    assert_response :success
    assert_select "h1", text: /Design review queue/
    assert_select ".ship-queue__project-title", text: /Design bot/
    assert_select ".ship-queue__project-title", text: /Build bot/, count: 0
  end

  test "the build queue lists only ship certifications" do
    get build_admin_certification_hardware_reviews_path

    assert_response :success
    assert_select "h1", text: /Build review queue/
    assert_select ".ship-queue__project-title", text: /Build bot/
    assert_select ".ship-queue__project-title", text: /Design bot/, count: 0
  end

  test "each queue counts only its own stage as waiting" do
    get design_admin_certification_hardware_reviews_path
    assert_select ".hardware-queue__vital--primary .hardware-queue__vital-value", text: "1"

    get build_admin_certification_hardware_reviews_path
    assert_select ".hardware-queue__vital--primary .hardware-queue__vital-value", text: "1"
  end

  test "the design queue shows the requested amount, the build queue shows hours" do
    get design_admin_certification_hardware_reviews_path
    assert_select ".hardware-queue__ask", text: "$42"

    get build_admin_certification_hardware_reviews_path
    assert_select ".hardware-queue__ask"
  end

  test "both queues are reachable from either one" do
    get design_admin_certification_hardware_reviews_path

    assert_response :success
    assert_select "a[href=?]", design_admin_certification_hardware_reviews_path
    assert_select "a[href=?]", build_admin_certification_hardware_reviews_path
  end

  test "the old combined queue url redirects to the design queue" do
    get admin_certification_hardware_reviews_path

    assert_redirected_to design_admin_certification_hardware_reviews_path
  end

  test "start reviewing stays within the queue it was started from" do
    get design_admin_certification_hardware_reviews_path

    assert_select "a[href=?]", next_admin_certification_hardware_reviews_path(stage: "design")
  end

  test "next on the build queue never hands back a design review" do
    get next_admin_certification_hardware_reviews_path(stage: "build")

    assert_redirected_to admin_certification_hardware_review_path(@build_project)
  end

  # Skipping goes through `next`. Without releasing first, the skipped review
  # stayed claimed by the skipper for the full TTL and no one else could pick
  # it up, so the queue slowly filled with invisible work.
  test "asking for the next review releases the one that was skipped" do
    ::Certification::FundingRequest.atomic_claim!(@funding.id, @reviewer)
    assert_equal @reviewer.id, @funding.reload.reviewer_id

    get next_admin_certification_hardware_reviews_path(stage: "design", skip: "funding:#{@funding.id}")

    assert_nil @funding.reload.reviewer_id, "the skipped request must go back to the queue"
    assert_nil @funding.claim_expires_at
    assert ::Certification::FundingRequest.available_for(other_reviewer).exists?(id: @funding.id)
  end

  # One dash, two queues: moving to a build review has to let go of a design
  # claim as well, or the other queue keeps the row hidden.
  test "asking for the next build review releases a held design claim" do
    ::Certification::FundingRequest.atomic_claim!(@funding.id, @reviewer)

    get next_admin_certification_hardware_reviews_path(stage: "build")

    assert_nil @funding.reload.reviewer_id
  end

  test "the design review page leads with the ask and the verdict form" do
    get admin_certification_hardware_review_path(@design_project)

    assert_response :success
    # The number the verdict turns on is a headline fact, not buried in a list.
    assert_select ".hardware-review__fact--primary dt", text: "Requested"
    assert_select ".hardware-review__fact--primary dd", text: "$42"
    assert_select ".hardware-review__tag", text: "Design funding"
    # Supporting context is present but folded away.
    assert_select "details.hardware-review__more .hardware-review__timeline"
  end

  test "the build review page leads with the effort instead of the ask" do
    get admin_certification_hardware_review_path(@build_project)

    assert_response :success
    assert_select ".hardware-review__fact--primary dt", text: "Hours logged"
    assert_select ".hardware-review__tag", text: "Build certification"
    assert_select ".hardware-review__fact--primary dt", text: "Requested", count: 0
  end

  test "the review page links back to its own queue" do
    get admin_certification_hardware_review_path(@design_project)
    assert_select "a[href=?]", design_admin_certification_hardware_reviews_path

    get admin_certification_hardware_review_path(@build_project)
    assert_select "a[href=?]", build_admin_certification_hardware_reviews_path
  end

  test "the review page offers the evidence links a reviewer opens" do
    @design_project.update_columns(repo_url: "https://github.com/x/y", demo_url: "https://example.com/demo")

    get admin_certification_hardware_review_path(@design_project)

    assert_select ".hardware-review__link", text: /Repo/
    assert_select ".hardware-review__link", text: /Demo/
    assert_select ".hardware-review__link", text: /Project page/
  end

  test "the queue carries a hardware-scoped my-stats modal" do
    get design_admin_certification_hardware_reviews_path

    assert_response :success
    assert_select "dialog#hardware-my-stats"
    # Both queues are represented, which the site-wide stats page can't do.
    assert_select "#hardware-my-stats tbody th", text: "Design"
    assert_select "#hardware-my-stats tbody th", text: "Build"
    assert_select "#hardware-my-stats a[href=?]", admin_certification_mystats_path
  end

  test "my-stats counts the reviewer's own decided hardware reviews" do
    HCBService.stub(:create_card_grant, HCB_GRANT_RESPONSE) do
      @funding.update!(reviewer: @reviewer, status: :approved, feedback: "looks good")
    end

    get design_admin_certification_hardware_reviews_path

    assert_response :success
    # Design row: 1 reviewed, 1 approved, 100% - none of which the ship-only
    # site-wide stats page would show.
    assert_select "#hardware-my-stats tbody tr:first-child td", text: "1", count: 2
    assert_select "#hardware-my-stats tbody tr:first-child td", text: "100%"
  end

  test "my-stats ignores reviews decided by someone else" do
    other = create_user(slack_id: "U_HWQ_OTHER", display_name: "hwq-other")
    other.grant_role!(:admin)
    HCBService.stub(:create_card_grant, HCB_GRANT_RESPONSE) do
      @funding.update!(reviewer: other, status: :approved, feedback: "not mine")
    end

    get design_admin_certification_hardware_reviews_path

    assert_select "#hardware-my-stats tbody tr:first-child td", text: "0", count: 3
  end

  # A reviewer working the queue shouldn't have to go back to the list between
  # verdicts.
  test "submitting a design verdict advances to the next review" do
    ::Certification::FundingRequest.atomic_claim!(@funding.id, @reviewer)
    HCBService.stub(:create_card_grant, HCB_GRANT_RESPONSE) do
      patch admin_certification_funding_request_path(@funding),
            params: { redirect_to_hardware: @design_project.id,
                      certification_funding_request: { verdict: "approved", feedback: "looks good" } }
    end

    assert_redirected_to next_admin_certification_hardware_reviews_path(stage: "design")
  end

  test "a reviewer can approve a design without issuing a grant" do
    ::Certification::FundingRequest.atomic_claim!(@funding.id, @reviewer)

    grant_called = false
    HCBService.stub(:create_card_grant, ->(*) { grant_called = true; HCB_GRANT_RESPONSE }) do
      patch admin_certification_funding_request_path(@funding),
            params: { redirect_to_hardware: @design_project.id,
                      certification_funding_request: { verdict: "approved_without_grant", feedback: "you're covered" } }
    end

    assert_not grant_called
    assert @funding.reload.approved_without_grant?
    assert_nil @funding.hcb_grant_hashid
    assert_equal "build", @design_project.reload.hardware_stage
  end

  test "an emptied design queue lands back on the design queue, not a dead end" do
    ::Certification::FundingRequest.atomic_claim!(@funding.id, @reviewer)
    HCBService.stub(:create_card_grant, HCB_GRANT_RESPONSE) do
      patch admin_certification_funding_request_path(@funding),
            params: { redirect_to_hardware: @design_project.id,
                      certification_funding_request: { verdict: "approved", feedback: "looks good" } }
    end
    follow_redirect!

    assert_redirected_to design_admin_certification_hardware_reviews_path
  end

  # The verdict form partial used to render its own unclaim button on top of the
  # page's, so a claimed design review showed two.
  test "a claimed design review shows exactly one unclaim button" do
    ::Certification::FundingRequest.atomic_claim!(@funding.id, @reviewer)

    get admin_certification_hardware_review_path(@design_project)

    assert_response :success
    assert_select "button[form=?]", "unclaim-form-#{@funding.id}", count: 1
  end

  test "a claimed build review shows exactly one unclaim button" do
    ::Certification::Ship.atomic_claim!(@ship.id, @reviewer)

    get admin_certification_hardware_review_path(@build_project)

    assert_response :success
    assert_select "button[form=?]", "unclaim-form-#{@ship.id}", count: 1
  end

  # The builder's note is context for the verdict, so it renders read-only on
  # the claimed design review form.
  test "the builder's submitter note shows on the design review form" do
    @funding.update!(submitter_note: "The display is a stretch goal.")
    ::Certification::FundingRequest.atomic_claim!(@funding.id, @reviewer)

    get admin_certification_hardware_review_path(@design_project)

    assert_response :success
    assert_select ".review-form__submitter-note-label", text: /Note from/
    assert_select ".review-form__submitter-note-body", text: /display is a stretch goal/
  end

  # No note, no empty block.
  test "the design review form omits the note block when there is none" do
    ::Certification::FundingRequest.atomic_claim!(@funding.id, @reviewer)

    get admin_certification_hardware_review_path(@design_project)

    assert_response :success
    assert_select ".review-form__submitter-note", count: 0
  end

  test "non-reviewers can't reach either queue" do
    sign_in @owner

    get design_admin_certification_hardware_reviews_path
    assert_response :forbidden

    get build_admin_certification_hardware_reviews_path
    assert_response :forbidden
  end

  # --- Flag for fraud ---------------------------------------------------------

  test "flagging a project for fraud creates a pending fraud report and notifies the fraud team" do
    assert_difference -> { ::Project::Report.where(reason: "fraud").count }, 1 do
      assert_enqueued_with(job: SendSlackDmJob) do
        post flag_for_fraud_admin_certification_hardware_review_path(@design_project),
             params: { details: "This looks like a resold kit rather than a real build." }
      end
    end

    report = ::Project::Report.where(reason: "fraud").order(:created_at).last
    assert_equal @design_project.id, report.project_id
    assert_equal @reviewer.id, report.reporter_id
    assert report.pending?
    assert_redirected_to admin_certification_hardware_review_path(@design_project)
  end

  test "flagging without details is rejected — a reason is required" do
    assert_no_difference -> { ::Project::Report.where(reason: "fraud").count } do
      post flag_for_fraud_admin_certification_hardware_review_path(@design_project)
    end

    assert_redirected_to admin_certification_hardware_review_path(@design_project)
  end

  test "flagging with a too-short typed reason is rejected" do
    assert_no_difference -> { ::Project::Report.where(reason: "fraud").count } do
      post flag_for_fraud_admin_certification_hardware_review_path(@design_project),
           params: { details: "too short" }
    end

    assert_redirected_to admin_certification_hardware_review_path(@design_project)
  end

  test "flagging the same project twice is idempotent on the unique index" do
    post flag_for_fraud_admin_certification_hardware_review_path(@design_project),
         params: { details: "First pass: the demo video looks staged and reused." }
    assert_equal 1, ::Project::Report.where(reason: "fraud", project: @design_project).count

    assert_no_difference -> { ::Project::Report.count } do
      post flag_for_fraud_admin_certification_hardware_review_path(@design_project),
           params: { details: "Second pass: same reviewer flags it again by mistake." }
    end

    assert_redirected_to admin_certification_hardware_review_path(@design_project)
  end

  test "a non-reviewer can't flag a project for fraud" do
    sign_in @owner

    assert_no_difference -> { ::Project::Report.count } do
      post flag_for_fraud_admin_certification_hardware_review_path(@design_project),
           params: { details: "A non-reviewer should never reach this action at all." }
    end

    assert_response :forbidden
  end

  # Skipping a build review records a per-reviewer skip and moves on, rather
  # than bouncing the reviewer straight back to the same submission.
  test "skipping a build review records a skip and advances" do
    post skip_admin_certification_hardware_reviews_path, params: { stage: "build", token: "ship:#{@ship.id}" }

    assert ::Certification::ReviewSkip.exists?(user: @reviewer, reviewable: @ship)
    assert_redirected_to next_admin_certification_hardware_reviews_path(stage: "build")
  end

  test "skipping a design review records a skip and advances" do
    post skip_admin_certification_hardware_reviews_path, params: { stage: "design", token: "funding:#{@funding.id}" }

    assert ::Certification::ReviewSkip.exists?(user: @reviewer, reviewable: @funding)
    assert_redirected_to next_admin_certification_hardware_reviews_path(stage: "design")
  end

  # The whole point of the fix: a skipped build review is not handed back to the
  # skipper (their only build item is now hidden, so the queue is empty), but a
  # different reviewer is still offered it right away.
  test "a skipped build review is hidden from the skipper yet offered to others" do
    ::Certification::ReviewSkip.record!(user: @reviewer, reviewable: @ship)

    get next_admin_certification_hardware_reviews_path(stage: "build")
    assert_redirected_to build_admin_certification_hardware_reviews_path

    sign_in other_reviewer
    get next_admin_certification_hardware_reviews_path(stage: "build")
    assert_redirected_to admin_certification_hardware_review_path(@build_project)
  end

  # End to end through the button: skipping a review you hold hands the claim
  # back (via next's release), so another reviewer is offered it right away.
  test "skipping a claimed build review releases it for another reviewer" do
    ::Certification::Ship.atomic_claim!(@ship.id, @reviewer)

    post skip_admin_certification_hardware_reviews_path, params: { stage: "build", token: "ship:#{@ship.id}" }
    follow_redirect!

    assert_nil @ship.reload.reviewer_id, "skipping must hand the claim back"
    assert ::Certification::Ship.available_for(other_reviewer).exists?(id: @ship.id)
  end

  test "a skipped design review is hidden from the skipper" do
    ::Certification::ReviewSkip.record!(user: @reviewer, reviewable: @funding)

    get next_admin_certification_hardware_reviews_path(stage: "design")
    assert_redirected_to design_admin_certification_hardware_reviews_path
  end

  # The skip is a cooldown, not a permanent pass: once it lapses the submission
  # comes back to the reviewer.
  test "a skip stops hiding the review once its cooldown lapses" do
    ::Certification::ReviewSkip.record!(user: @reviewer, reviewable: @ship)

    travel_to(::Certification::ReviewSkip::SKIP_COOLDOWN.from_now + 1.minute) do
      get next_admin_certification_hardware_reviews_path(stage: "build")
      assert_redirected_to admin_certification_hardware_review_path(@build_project)
    end
  end

  test "a claimed build review offers a skip button posting to the skip path" do
    ::Certification::Ship.atomic_claim!(@ship.id, @reviewer)

    get admin_certification_hardware_review_path(@build_project)

    assert_response :success
    assert_select "button[form=?]", "skip-form-#{@ship.id}", count: 1
    assert_select "form[action=?]", skip_admin_certification_hardware_reviews_path(stage: "build")
  end

  test "a claimed design review offers a skip button posting to the skip path" do
    ::Certification::FundingRequest.atomic_claim!(@funding.id, @reviewer)

    get admin_certification_hardware_review_path(@design_project)

    assert_response :success
    assert_select "button[form=?]", "skip-form-#{@funding.id}", count: 1
    assert_select "form[action=?]", skip_admin_certification_hardware_reviews_path(stage: "design")
  end

  test "the review page shows a flag-for-fraud button when the project is not flagged" do
    ::Certification::FundingRequest.atomic_claim!(@funding.id, @reviewer)

    get admin_certification_hardware_review_path(@design_project)

    assert_response :success
    assert_select "form[action=?]", flag_for_fraud_admin_certification_hardware_review_path(@design_project)
    assert_select "button", text: /Flag for fraud/
    assert_select ".hardware-review__fraud-flagged", count: 0
  end

  test "the review page shows the flagged state while a pending fraud report exists" do
    @design_project.reports.create!(
      reporter: @reviewer, reason: "fraud", status: :pending,
      details: "Looks like a resold kit, not a real build."
    )
    ::Certification::FundingRequest.atomic_claim!(@funding.id, @reviewer)

    get admin_certification_hardware_review_path(@design_project)

    assert_response :success
    assert_select ".hardware-review__fraud-flagged-badge", text: /Flagged for fraud review/
    assert_select ".hardware-review__fraud-flagged", text: /#{@reviewer.display_name}/
    # The button and its modal give way to the flagged state.
    assert_select "form[action=?]", flag_for_fraud_admin_certification_hardware_review_path(@design_project), count: 0
  end

  test "the fraud-report status card is always shown in the details column" do
    # No claim held: the status card lives in the details column, not the
    # claim-gated sidebar, so it renders regardless of who holds the review.
    get admin_certification_hardware_review_path(@design_project)
    assert_response :success
    assert_select ".hardware-review__fraud-status", text: /No fraud report on this project/

    @design_project.reports.create!(
      reporter: @reviewer, reason: "fraud", status: :pending,
      details: "Looks like a resold kit, not a real build."
    )
    get admin_certification_hardware_review_path(@design_project)
    assert_select ".hardware-review__fraud-status .hardware-review__fraud-flagged-badge",
          text: /Flagged for fraud review/
  end

  private

  # A second reviewer, to prove a released claim is actually offered onward.
  def other_reviewer
    @other_reviewer ||= begin
      user = create_user(slack_id: "U_HWQ_REV2", display_name: "hwq-reviewer-2")
      user.grant_role!(:admin)
      user
    end
  end

  def add_devlog(project)
    devlog = Post::Devlog.new(body: "initial log", duration_seconds: 3600, phase: project.hardware_stage)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: @owner, postable: devlog)
  end

  def hardware_project(title, stage)
    project = Project.create!(title: title)
    project.memberships.create!(user: @owner, role: :owner)
    project.update!(hardware_stage: stage)
    project
  end
end
