require "test_helper"

# A reviewer who opens a hardware submission that belongs in the other queue
# flags it instead of deciding it, and the builder answers on their project page.
class HardwareQueueMismatchTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:hardware_flow)
    Flipper.enable(:week_1_release)

    @owner = create_user(slack_id: "U_QM_OWNER", display_name: "qm-owner", verified: true)
    @reviewer = create_user(slack_id: "U_QM_REV", display_name: "qm-rev")
    @reviewer.grant_role!(:admin)
    @outsider = create_user(slack_id: "U_QM_OUT", display_name: "qm-out", verified: true)
  end

  teardown do
    Flipper.disable(:hardware_flow)
    Flipper.disable(:week_1_release)
  end

  # --- design queue: "you've already built this" -----------------------------

  test "flagging a funding request pulls it out of the design queue and asks the owner" do
    project, request = design_project_with_request

    sign_in @reviewer
    assert_difference -> { @owner.notifications.count }, 1 do
      post flag_queue_mismatch_admin_certification_funding_request_path(request),
           params: { reason: "This looks finished already" }
    end

    assert request.reload.misfiled?
    assert_equal @reviewer, request.reviewer
    assert_equal "This looks finished already", request.internal_reason
    assert_not Certification::FundingRequest.available_for(@reviewer).exists?(id: request.id)
    assert_equal "Notifications::Hardware::ReviewQueueMismatch",
                 @owner.notifications.order(:id).last.type
  end

  # Routing isn't reviewing: no verdict, no bounty, and it stays out of the
  # numbers a reviewer is measured on.
  test "flagging records no decision and earns no bounty" do
    project, request = design_project_with_request

    sign_in @reviewer
    post flag_queue_mismatch_admin_certification_funding_request_path(request)

    request.reload
    assert_nil request.decided_at
    assert_nil request.stardust_earned
    assert_not request.decided?
    assert_equal 0, Certification::FundingRequest.reviewed_today(@reviewer)
  end

  test "confirming the build is done moves the project to build and re-files design devlogs" do
    project, request = design_project_with_request
    devlog = project.devlogs.first
    assert_equal "design", devlog.phase

    sign_in @reviewer
    post flag_queue_mismatch_admin_certification_funding_request_path(request)

    sign_in @owner
    patch project_queue_mismatch_path(project)

    assert request.reload.withdrawn?
    assert_equal "build", project.reload.hardware_stage
    assert_equal "build", devlog.reload.phase
  end

  test "the owner can dispute and the request goes straight back to the queue" do
    project, request = design_project_with_request

    sign_in @reviewer
    post flag_queue_mismatch_admin_certification_funding_request_path(request)

    sign_in @owner
    delete project_queue_mismatch_path(project)

    assert request.reload.pending?
    assert_nil request.reviewer_id, "should be unclaimed so the next reviewer picks it up"
    assert Certification::FundingRequest.available_for(@reviewer).exists?(id: request.id)
  end

  # --- build queue: "you should get funded first" ----------------------------

  test "flagging a ship hides the ship event from every public surface" do
    project, ship, ship_event = build_project_with_ship

    sign_in @reviewer
    post flag_queue_mismatch_admin_certification_ship_path(ship)

    assert ship.reload.misfiled?
    assert_equal "misfiled", ship_event.reload.certification_status
    assert_includes Post::ShipEvent::HIDDEN_STATUSES, ship_event.certification_status
  end

  # The whole point of the private post: nobody but the team may see it.
  test "a misfiled ship is invisible to outsiders but visible to its owner" do
    project, ship, ship_event = build_project_with_ship

    sign_in @reviewer
    post flag_queue_mismatch_admin_certification_ship_path(ship)

    sign_in @outsider
    get project_path(project)
    assert_response :success
    assert_select ".project-show__latest-ship", count: 0
    assert_select ".queue-mismatch-card", count: 0

    sign_in @owner
    get project_path(project)
    assert_response :success
    assert_select ".queue-mismatch-card"
    assert_select ".queue-mismatch-card__badge", text: /Only you can see this/
    # The card replaces the ship rather than sitting next to it: a withdrawn
    # ship still on the timeline reads as a live one.
    assert_select ".project-show__latest-ship", count: 0
  end

  test "disputing puts the ship post back on the owner's timeline" do
    project, ship, ship_event = build_project_with_ship

    sign_in @reviewer
    post flag_queue_mismatch_admin_certification_ship_path(ship)

    sign_in @owner
    get project_path(project)
    assert_select ".project-show__latest-ship", count: 0

    delete project_queue_mismatch_path(project)
    get project_path(project)

    assert_select ".project-show__latest-ship"
    assert_select ".queue-mismatch-card", count: 0
  end

  # Without rolling the review state back, `shipped?` stays true off the
  # leftover ship_status/shipped_at and the project keeps behaving as though it
  # has a live ship: no mission can be attached and deletion needs force.
  test "converting a real ship clears the project's shipped state" do
    project, ship, _ship_event = build_project_with_ship
    # What Projects::ShipsController#create leaves behind on a genuine ship;
    # set directly because submit_for_review! guards on shippable?.
    project.update_columns(ship_status: "submitted", shipped_at: Time.current)
    assert project.reload.shipped?

    sign_in @reviewer
    post flag_queue_mismatch_admin_certification_ship_path(ship)
    sign_in @owner
    patch project_queue_mismatch_path(project)

    project.reload
    assert_equal "draft", project.ship_status
    assert_nil project.shipped_at
    assert_not project.shipped?
  end

  # An earlier approved ship is the state worth keeping, so a later withdrawal
  # must not wipe it.
  test "converting does not roll back a project with an earlier real ship" do
    project, ship, _ship_event = build_project_with_ship
    earlier = Post::ShipEvent.new(body: "the first ship", uploading_attachments: true)
    earlier.save!(validate: false)
    Post.create!(project: project, user: @owner, postable: earlier)
    earlier.update!(certification_status: "approved")
    project.update_columns(ship_status: "approved", shipped_at: Time.current)

    sign_in @reviewer
    post flag_queue_mismatch_admin_certification_ship_path(ship)
    sign_in @owner
    patch project_queue_mismatch_path(project)

    assert_equal "approved", project.reload.ship_status
    assert_not_nil project.shipped_at
  end

  test "a misfiled ship stays out of the home feed" do
    project, ship, ship_event = build_project_with_ship
    assert_includes Gorse::PostPayload.feed_scope(@outsider).pluck(:id), ship_event.post.id

    sign_in @reviewer
    post flag_queue_mismatch_admin_certification_ship_path(ship)

    assert_not_includes Gorse::PostPayload.feed_scope(@outsider).pluck(:id), ship_event.post.id
  end

  test "confirming funding is needed sends the project back to the design stage" do
    project, ship, _ship_event = build_project_with_ship

    sign_in @reviewer
    post flag_queue_mismatch_admin_certification_ship_path(ship)

    sign_in @owner
    patch project_queue_mismatch_path(project)

    assert ship.reload.withdrawn?
    assert_equal "design", project.reload.hardware_stage
  end

  # The point of excluding misfiled ships from Project#last_ship_event: without
  # it the builder would have to post a fresh devlog before they could resubmit.
  test "the owner can submit a funding request immediately after converting" do
    project, ship, _ship_event = build_project_with_ship

    sign_in @reviewer
    post flag_queue_mismatch_admin_certification_ship_path(ship)

    sign_in @owner
    patch project_queue_mismatch_path(project)

    assert project.reload.has_devlog_since_last_ship?,
           "the withdrawn ship must not gate the next submission"
    assert_difference -> { project.certification_funding_requests.count }, 1 do
      post project_funding_request_path(project),
           params: { complexity_tier: 2, requested_amount: 40 }
    end
    assert project.certification_funding_requests.order(:id).last.pending?
  end

  test "disputing puts the ship back into the build queue and back on the feed" do
    project, ship, ship_event = build_project_with_ship

    sign_in @reviewer
    post flag_queue_mismatch_admin_certification_ship_path(ship)

    sign_in @owner
    delete project_queue_mismatch_path(project)

    assert ship.reload.pending?
    assert_equal "pending", ship_event.reload.certification_status
    assert_includes Gorse::PostPayload.feed_scope(@outsider).pluck(:id), ship_event.post.id
  end

  # --- already-funded warning ------------------------------------------------
  #
  # Prize redemption is unique per funding request, not per project, so a funded
  # project sent back to design can be funded a second time. The reviewer is
  # warned rather than blocked: a genuinely mis-issued kit is a real case.

  test "the flag form warns when the project already took a grant" do
    project, ship, _ship_event = build_project_with_ship
    funded_with_grant(project, dollars: 40)

    sign_in @reviewer
    get admin_certification_hardware_review_path(project)

    assert_select ".hardware-review__mismatch-warning", text: /already received a \$40 grant/
    assert_select ".hardware-review__mismatch-warning", text: /funded a second time/
  end

  test "the flag form names the kit when the project already took one" do
    project, ship, _ship_event = build_project_with_ship
    kit = funded_with_kit(project)

    sign_in @reviewer
    get admin_certification_hardware_review_path(project)

    assert_select ".hardware-review__mismatch-warning", text: /already received the #{kit.name}/
  end

  # An approval that handed over neither a grant nor a kit costs nothing to
  # undo, so it must not cry wolf.
  test "a waived approval raises no warning" do
    project, ship, _ship_event = build_project_with_ship
    request = funded_with_grant(project, dollars: 40)
    request.update!(prizes_waived: true, approved_amount_cents: 0)

    sign_in @reviewer
    get admin_certification_hardware_review_path(project)

    assert_select ".hardware-review__mismatch-warning", count: 0
    assert_select ".hardware-review__mismatch"
  end

  test "an unfunded project raises no warning" do
    project, ship, _ship_event = build_project_with_ship

    sign_in @reviewer
    get admin_certification_hardware_review_path(project)

    assert_select ".hardware-review__mismatch-warning", count: 0
    assert_select ".hardware-review__mismatch"
  end

  # The design queue can't send anything "back to funding", so the warning has
  # no business there.
  test "the design side never shows the warning" do
    project, request = design_project_with_request

    sign_in @reviewer
    get admin_certification_hardware_review_path(project)

    assert_select ".hardware-review__mismatch-warning", count: 0
  end

  # --- review history --------------------------------------------------------

  # Disputing rewinds the review to pending in place, so the bounce leaves no
  # record of its own. Without this the next reviewer sees a clean slate.
  test "a disputed flag still shows in the review history" do
    project, ship, _ship_event = build_project_with_ship

    sign_in @reviewer
    post flag_queue_mismatch_admin_certification_ship_path(ship),
         params: { reason: "Get a parts grant first" }
    sign_in @owner
    delete project_queue_mismatch_path(project)

    assert ship.reload.pending?, "precondition: the dispute put it back in the queue"

    sign_in @reviewer
    get admin_certification_hardware_review_path(project)

    assert_select ".hardware-review__history-item--bounced" do
      assert_select ".hardware-review__timeline-meta", text: /Flagged as the wrong queue/
      assert_select ".hardware-review__history-feedback--internal", text: /Get a parts grant first/
    end
    assert_select ".ship-review__description", text: /first review on this project/, count: 0
  end

  test "a review that was never flagged shows no bounce notice" do
    project, _ship, _ship_event = build_project_with_ship

    sign_in @reviewer
    get admin_certification_hardware_review_path(project)

    assert_select ".hardware-review__history-item--bounced", count: 0
    assert_select ".ship-review__description", text: /first review on this project/
  end

  # --- authorization ---------------------------------------------------------

  test "an outsider cannot answer someone else's queue question" do
    project, ship, _ship_event = build_project_with_ship

    sign_in @reviewer
    post flag_queue_mismatch_admin_certification_ship_path(ship)

    sign_in @outsider
    patch project_queue_mismatch_path(project)

    assert_response :forbidden
    assert ship.reload.misfiled?
  end

  test "a non-reviewer cannot flag a submission" do
    _project, request = design_project_with_request

    sign_in @outsider
    post flag_queue_mismatch_admin_certification_funding_request_path(request)

    assert_response :forbidden
    assert request.reload.pending?
  end

  private

  def design_project_with_request
    project = Project.create!(title: "Design bot #{SecureRandom.hex(3)}", hardware_stage: "design")
    project.memberships.create!(user: @owner, role: :owner)
    add_devlog(project, "design")
    request = project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 4_000, status: :pending
    )
    # Re-routing sits behind the same claim the verdict does.
    Certification::FundingRequest.atomic_claim!(request.id, @reviewer)
    [ project, request.reload ]
  end

  def build_project_with_ship
    project = Project.create!(title: "Build bot #{SecureRandom.hex(3)}", hardware_stage: "build")
    project.memberships.create!(user: @owner, role: :owner)
    add_devlog(project, "build")

    ship_event = Post::ShipEvent.new(body: "shipped it", uploading_attachments: true)
    ship_event.save!(validate: false)
    Post.create!(project: project, user: @owner, postable: ship_event)
    ship = project.ship_reviews.create!(status: :pending, post_ship_event_id: ship_event.id)
    Certification::Ship.atomic_claim!(ship.id, @reviewer)

    [ project, ship.reload, ship_event ]
  end

  # A project that already had a design approval pay out a grant. Built in the
  # design stage (the only stage that accepts a request) then moved to build.
  def funded_with_grant(project, dollars:)
    project.update_columns(hardware_stage: "design")
    request = project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: dollars * 100, status: :pending
    )
    HCBService.stub(:create_card_grant, { "id" => "qm_grant" }) do
      request.update!(reviewer: @reviewer, verdict: "approved")
    end
    project.update_columns(hardware_stage: "build")
    request
  end

  def funded_with_kit(project)
    mission = create_mission
    mission.update!(hardware: true)
    project.mission_attachments.create!(mission: mission)
    kit = ShopItem.new(name: "Hackpad Kit #{SecureRandom.hex(3)}", description: "the kit",
                       ticket_cost: 0, type: "ShopItem::ThirdPartyPhysical",
                       enabled: true, mission_prize_only: true)
    kit.image.attach(io: StringIO.new(Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
    )), filename: "kit.png", content_type: "image/png")
    kit.save!
    mission.prizes.create!(shop_item: kit, position: 0, category: :after_design)

    project.update_columns(hardware_stage: "design")
    request = project.certification_funding_requests.create!(user: @owner, status: :pending)
    request.update!(reviewer: @reviewer, verdict: "approved")
    project.update_columns(hardware_stage: "build")
    kit
  end

  def add_devlog(project, phase)
    devlog = Post::Devlog.new(body: "log", duration_seconds: 3600, phase: phase)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: @owner, postable: devlog)
    devlog
  end
end
