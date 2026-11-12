require "test_helper"

class Admin::ViralityReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.identities.find_or_create_by!(provider: "hack_club") do |identity|
      identity.uid = "virality-test-hca"
      identity.access_token = "test-token"
    end
    @mention = project_mentions(:virality_pending)
    @mention.project.update!(ship_status: "approved")
    @mention.project.memberships.find_by!(user: @user).update!(role: :owner)
  end

  test "admins and super admins can view the dashboard and evidence links" do
    %w[admin super_admin].each do |role|
      @user.update!(granted_roles: [ role ])
      sign_in @user
      get admin_virality_reviews_path(mention_id: @mention.id)
      assert_response :success
      assert_select "h1", "Virality reviews"
      assert_select "a[href=?]", @mention.url
      assert_select "input[name='decision[evidence][metric_value]']"
    end
  end

  test "reviewers cannot view, schedule, cancel or poll decisions" do
    @user.update!(granted_roles: [ "project_certifier" ])
    sign_in @user
    get admin_virality_reviews_path
    assert_response :forbidden
    post admin_virality_review_path(@mention), params: { decision: { action: "reject", reason: "No reach" } }
    assert_response :forbidden
    get admin_virality_review_path(0), as: :json
    assert_response :forbidden
    post cancel_admin_virality_review_path(0)
    assert_response :forbidden
  end

  test "deleted projects remain visible in the queue and detail without allowing approval" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in @user
    @mention.project.update!(deleted_at: Time.current)

    [ admin_virality_reviews_path, admin_virality_reviews_path(mention_id: @mention.id) ].each do |path|
      get path
      assert_response :success
      assert_select "h2", @mention.project.title
      assert_select "p", "Project status: Deleted"
      assert_select "button[value='approve'][disabled]"
      assert_select "button[value='reject']:not([disabled])"
    end
  end

  test "admins can stop a scheduled decision after its project is deleted" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in @user
    post admin_virality_review_path(@mention), params: { decision: { action: "reject", reason: "No independent reach" } }
    decision = @mention.virality_decisions.last
    @mention.project.update!(deleted_at: Time.current)

    get admin_virality_reviews_path(queue: "scheduled", mention_id: @mention.id)
    assert_response :success
    assert_select "form[action=?]", cancel_admin_virality_review_path(decision)
    post cancel_admin_virality_review_path(decision)
    assert_equal "cancelled", decision.reload.status
    follow_redirect!
    assert_response :success
  end

  test "admin schedules and stops a decision with an accessible audit trail" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in @user
    post admin_virality_review_path(@mention), params: { decision: { action: "reject", reason: "Link is not evidence of reach" } }
    decision = @mention.virality_decisions.last
    assert_equal "scheduled", decision.status
    follow_redirect!
    assert_response :success
    assert_select "form[action=?]", cancel_admin_virality_review_path(decision)
    get admin_virality_review_path(decision), as: :json
    assert_equal "scheduled", response.parsed_body["status"]
    post cancel_admin_virality_review_path(decision)
    assert_equal "cancelled", decision.reload.status
    follow_redirect!
    assert_response :success
    assert_select "a", "Audit details"
  end

  test "virality audits are restricted to admins including super admins" do
    version = PaperTrail::Version.create!(item: @mention, event: "virality_reject", whodunnit: @user.id.to_s)
    @user.update!(granted_roles: [ "fraud_dept" ])
    sign_in @user
    get admin_audit_logs_path(item_type: "ProjectMention", item_id: @mention.id)
    assert_response :success
    assert_select "a[href=?]", admin_audit_log_path(version), count: 0
    get admin_audit_log_path(version)
    assert_response :forbidden

    @user.update!(granted_roles: [ "super_admin" ])
    sign_in @user
    get admin_audit_log_path(version)
    assert_response :success
  end

  test "triage saves reviewer notes and checklist with an audit entry, and hold moves the mention to its own queue" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in @user
    post triage_admin_virality_review_path(@mention), params: {
      mention: { internal_notes: "waiting for DM answer", extra_links: "https://example.com/more", review_checklist: [ "", "Original work" ], on_hold: "1" }
    }
    assert_redirected_to admin_virality_reviews_path(queue: "pending")

    @mention.reload
    assert_equal "waiting for DM answer", @mention.internal_notes
    assert_equal [ "Original work" ], @mention.review_checklist
    assert @mention.on_hold_at?
    assert_includes @mention.evidence_urls, "https://example.com/more"
    assert_equal @user.id.to_s, @mention.versions.find_by!(event: "virality_triage").whodunnit

    get admin_virality_reviews_path(queue: "on_hold")
    assert_select ".virality-review__item strong", @mention.project.title
    assert_select "textarea[name='mention[internal_notes]']", "waiting for DM answer"
  end

  test "approval needs the whole checklist and moves on to the next submission" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in @user
    decision = { action: "approve", tier: "good", evidence: { platform: "GitHub", metric_name: "stars", metric_value: "30" } }

    post admin_virality_review_path(@mention), params: { decision: decision, mention: { review_checklist: [ "Original work" ] } }
    assert_empty @mention.virality_decisions

    post admin_virality_review_path(@mention), params: { decision: decision, mention: { review_checklist: ProjectMention::ELIGIBILITY_CHECKS } }
    assert_equal "1", @mention.virality_decisions.last.evidence["eligibility_confirmed"]
    assert_redirected_to admin_virality_reviews_path(queue: "pending")
    follow_redirect!
    assert_select ".virality-review__undo form[action=?]", cancel_admin_virality_review_path(@mention.virality_decisions.last)
  end

  test "triage is refused while a decision is scheduled" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in @user
    post admin_virality_review_path(@mention), params: { decision: { action: "reject", reason: "No reach" } }
    post triage_admin_virality_review_path(@mention), params: { mention: { internal_notes: "late edit" } }
    assert_nil @mention.reload.internal_notes
    assert_equal "scheduled", @mention.virality_decisions.last.status
  end

  test "imported verdicts wait under reviewed until a reviewer confirms them" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in @user
    @mention.update!(proposed_action: "reject", reviewer_notes: "Seems like a duplicate!")

    get admin_virality_reviews_path(queue: "reviewed")
    assert_response :success
    assert_select ".virality-review__item-proposal", "Reject · awaiting confirmation"
    assert_select ".virality-review__proposal"
    assert_select "textarea[name='decision[reason]']", "Seems like a duplicate!"
    assert_equal :pending, @mention.reload.status

    post admin_virality_review_path(@mention), params: { queue: "reviewed", decision: { action: "reject", reason: "Seems like a duplicate!" } }
    decision = @mention.virality_decisions.last
    travel_to decision.process_at + 1.second do
      assert decision.process!
    end
    @mention.reload
    assert_equal :rejected, @mention.status
    assert_nil @mention.proposed_action
  end

  test "a proposed verdict can be sent back to the review queue" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in @user
    @mention.update!(proposed_action: "approve", proposed_tier: "great")
    post triage_admin_virality_review_path(@mention), params: { queue: "reviewed", mention: { dismiss_proposal: "1" } }
    @mention.reload
    assert_nil @mention.proposed_action
    assert_nil @mention.proposed_tier
  end
end
