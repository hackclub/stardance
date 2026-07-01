require "test_helper"

class Admin::ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user(slack_id: "U_ADMIN_PROJECTS", display_name: "adminprojects")
    @admin.update!(granted_roles: %w[admin])

    @owner = create_user(slack_id: "U_ADMIN_PROJECT_OWNER", display_name: "adminprojectowner")
    @project = Project.create!(title: "Wrong Kind", hardware_stage: "design")
    @project.memberships.create!(user: @owner, role: :owner)
  end

  test "admin can change project kind through the funding lock with audit log" do
    funding_request = @project.certification_funding_requests.new(
      user: @owner,
      complexity_tier: 1,
      requested_amount_cents: 5_000,
      status: :pending
    )
    funding_request.save!(validate: false)

    locked_project = @project.reload
    locked_project.hardware_stage = "build"
    assert_not locked_project.valid?
    assert_includes locked_project.errors[:hardware_stage], "cannot be changed after a funding request has been submitted"

    sign_in @admin

    assert_difference -> { PaperTrail::Version.where(item_type: "Project", item_id: @project.id.to_s).count }, 1 do
      patch update_hardware_stage_admin_project_path(@project), params: {
        hardware_stage: "build",
        reason: "Project was submitted as the wrong hardware stage after review."
      }
    end

    assert_redirected_to admin_project_path(@project)
    assert_equal "build", @project.reload.hardware_stage

    version = PaperTrail::Version.where(item_type: "Project", item_id: @project.id.to_s).order(:created_at).last
    assert_equal "admin_hardware_stage_update", version.event
    assert_equal @admin.id.to_s, version.whodunnit
    assert_equal [ "design", "build" ], version.object_changes["hardware_stage"]
    assert_equal "Project was submitted as the wrong hardware stage after review.", version.object_changes["reason"]
    assert_equal true, version.object_changes["funding_lock_bypassed"]
  end

  test "overriding to software clears a stale Hardware classifier so the project rejoins the queue" do
    @project.update_columns(project_type: "Hardware")

    sign_in @admin

    patch update_hardware_stage_admin_project_path(@project), params: {
      hardware_stage: "",
      reason: "AI mislabeled this; it's actually software."
    }

    @project.reload
    assert_nil @project.hardware_stage
    assert_nil @project.project_type, "stale Hardware classifier should be cleared on a software override"

    version = PaperTrail::Version.where(item_type: "Project", item_id: @project.id.to_s).order(:created_at).last
    assert_equal "admin_hardware_stage_update", version.event
    assert_equal [ "Hardware", nil ], version.object_changes["project_type"]
  end

  test "software override clears the classifier even when the project is already software" do
    # hardware_stage already nil (software), but the AI mislabeled it Hardware.
    already_software = Project.create!(title: "Mislabeled SW", project_type: "Hardware")
    already_software.memberships.create!(user: @owner, role: :owner)

    sign_in @admin

    patch update_hardware_stage_admin_project_path(already_software), params: {
      hardware_stage: "",
      reason: "AI mislabeled this; it's software and should be reviewable."
    }

    already_software.reload
    assert_nil already_software.hardware_stage
    assert_nil already_software.project_type, "stale Hardware classifier should clear even with no stage change"

    version = PaperTrail::Version.where(item_type: "Project", item_id: already_software.id.to_s).order(:created_at).last
    assert_equal "admin_hardware_stage_update", version.event
    assert_equal [ "Hardware", nil ], version.object_changes["project_type"]
  end

  test "helper cannot change project kind" do
    helper = create_user(slack_id: "U_HELPER_PROJECTS", display_name: "helperprojects")
    helper.update!(granted_roles: %w[helper])
    sign_in helper

    patch update_hardware_stage_admin_project_path(@project), params: {
      hardware_stage: "build",
      reason: "Trying without permission."
    }, as: :json

    assert_response :forbidden
    assert_equal "design", @project.reload.hardware_stage
  end

  test "admin can soft-reset the latest ship to draft without deleting anything" do
    ship_event = Post::ShipEvent.create!(body: "Shipped as software", certification_status: "returned", hours_at_ship: 1)
    Post.create!(project: @project, user: @owner, postable: ship_event)
    review = @project.ship_reviews.create!(status: :returned, feedback: "Please switch this to hardware.")
    Certification::Ysws.create!(post_ship_event: ship_event, ship_cert: review, project: @project, user: @owner, original_minutes: 60)
    @project.update_columns(ship_status: "needs_changes", shipped_at: Time.current)

    sign_in @admin

    # Nothing is deleted — the ship event, review and YSWS link all survive.
    assert_no_difference [ "Post::ShipEvent.count", "Certification::Ship.count", "Certification::Ysws.count" ] do
      post reset_latest_ship_admin_project_path(@project), params: {
        reason: "Converted to hardware; resetting the software ship."
      }
    end

    assert_redirected_to admin_project_path(@project)
    @project.reload
    assert_equal "draft", @project.ship_status
    assert_nil @project.shipped_at
    assert_equal ship_event, @project.last_ship_event, "the ship event is preserved"
    assert_equal "pending", ship_event.reload.certification_status, "certification is reset so it no longer blocks re-shipping"

    version = PaperTrail::Version.where(item_type: "Project", item_id: @project.id.to_s).order(:created_at).last
    assert_equal "admin_reset_latest_ship", version.event
    assert_equal [ "needs_changes", "draft" ], version.object_changes["ship_status"]
    assert_equal [ "returned", "pending" ], version.object_changes["certification_status"]
  end

  test "cannot reset a ship that has already paid out" do
    ship_event = Post::ShipEvent.create!(body: "Paid", certification_status: "approved", hours_at_ship: 1, payout: 42.0)
    Post.create!(project: @project, user: @owner, postable: ship_event)
    @project.update_column(:ship_status, "approved")

    sign_in @admin

    post reset_latest_ship_admin_project_path(@project), params: { reason: "trying to reset a paid ship" }

    assert_redirected_to admin_project_path(@project)
    assert_equal "approved", @project.reload.ship_status
    assert_equal "approved", ship_event.reload.certification_status
  end

  test "resetting the latest ship requires a reason" do
    ship_event = Post::ShipEvent.create!(body: "x", certification_status: "returned", hours_at_ship: 1)
    Post.create!(project: @project, user: @owner, postable: ship_event)
    @project.update_column(:ship_status, "needs_changes")

    sign_in @admin

    post reset_latest_ship_admin_project_path(@project), params: { reason: "   " }

    assert_redirected_to admin_project_path(@project)
    assert_equal "needs_changes", @project.reload.ship_status
  end

  test "helper cannot reset the latest ship" do
    ship_event = Post::ShipEvent.create!(body: "x", certification_status: "returned", hours_at_ship: 1)
    Post.create!(project: @project, user: @owner, postable: ship_event)

    helper = create_user(slack_id: "U_HELPER_CLEAR", display_name: "helperclear")
    helper.update!(granted_roles: %w[helper])
    sign_in helper

    post reset_latest_ship_admin_project_path(@project), params: { reason: "no perms" }, as: :json

    assert_response :forbidden
    assert_equal "returned", ship_event.reload.certification_status
  end

  test "resetting the latest ship closes a pending review so it leaves the queue" do
    project = Project.create!(title: "Submitted software")
    project.memberships.create!(user: @owner, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Submitted", certification_status: "pending", hours_at_ship: 1)
    Post.create!(project: project, user: @owner, postable: ship_event)
    reviewer = create_user(slack_id: "U_REVIEWER_RESET", display_name: "reviewerreset")
    review = project.ship_reviews.create!(status: :pending, reviewer: reviewer, claimed_at: Time.current, claim_expires_at: 30.minutes.from_now)
    project.update_columns(ship_status: "submitted", shipped_at: Time.current)

    sign_in @admin
    assert_includes Certification::Ship.available_for(reviewer), review, "baseline: the pending review is in the queue"

    assert_no_difference "Certification::Ship.count" do
      post reset_latest_ship_admin_project_path(project), params: { reason: "Reset so the owner can re-ship." }
    end

    review.reload
    assert_equal "returned", review.status, "pending review is resolved, not left stale"
    assert_nil review.reviewer_id, "claim released"
    assert_not_includes Certification::Ship.available_for(reviewer), review
  end

  test "converting to hardware closes the open software review so it isn't misrouted" do
    project = Project.create!(title: "Software that's really hardware")
    project.memberships.create!(user: @owner, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Submitted", certification_status: "pending", hours_at_ship: 1)
    Post.create!(project: project, user: @owner, postable: ship_event)
    review = project.ship_reviews.create!(status: :pending)
    project.update_column(:ship_status, "submitted")

    sign_in @admin

    assert_no_difference "Certification::Ship.count" do
      patch update_hardware_stage_admin_project_path(project), params: {
        hardware_stage: "design",
        reason: "This is a hardware project."
      }
    end

    assert_equal "design", project.reload.hardware_stage
    review.reload
    assert_equal "returned", review.status, "the software review is closed when the project becomes hardware"
    assert_nil review.reviewer_id
  end
end
