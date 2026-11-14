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

    get admin_virality_reviews_path
    assert_response :success
    assert_select "h2", @mention.project.title
    assert_select ".virality-review__flag--bad", "Project is deleted"
    assert_select "button[value='approve'][disabled]"
    assert_select "button[value='reject']:not([disabled])"

    get admin_virality_reviews_path(mention_id: @mention.id)
    assert_response :success
    assert_select "p", "Project status: Deleted"
    assert_select "button[value='approve'][disabled]"
    assert_select "button[value='reject']:not([disabled])"
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
    assert_select ".virality-review__item-note", "Internal: waiting for DM answer"
    assert_select "button[value='release']"

    get admin_virality_reviews_path(queue: "on_hold", mention_id: @mention.id)
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
    assert_select ".virality-review__item .virality-review__tag--awaiting-confirmation", "1 awaiting confirmation"
    assert_select ".virality-review__group-mention", text: /Imported: Reject/
    assert_select "textarea[name='reason']", "Seems like a duplicate!"

    get admin_virality_reviews_path(queue: "reviewed", mention_id: @mention.id)
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
  test "a project opens with every mention, repeats grouped" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in @user
    repeat = @mention.project.mentions.create!(url: "#{@mention.url}/")

    get admin_virality_reviews_path(project_id: @mention.project_id)
    assert_response :success
    assert_select ".virality-review__group", 2
    assert_select ".virality-review__repeat", "×2"
    assert_select "input[name='mention_ids[]'][value=?]", repeat.id.to_s
    assert_select "input[name='mention_ids[]'][value=?]", project_mentions(:virality_second).id.to_s
    assert_select ".virality-review__flag--bad", /repeat submission/
  end

  test "search finds projects by link and keeps the queue" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in @user

    get admin_virality_reviews_path(q: "example/project")
    assert_select ".virality-review__item strong", @mention.project.title
    get admin_virality_reviews_path(q: "nothing-matches-this")
    assert_select ".virality-review__item", 0
  end

  test "batch approval schedules every selected mention with its own evidence" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in @user
    second = project_mentions(:virality_second)

    post batch_admin_virality_reviews_path, params: {
      project_id: @mention.project_id, mention_ids: [ @mention.id, second.id ], operation: "approve",
      reason: "Nice reach", review_checklist: ProjectMention::ELIGIBILITY_CHECKS,
      evidence: {
        @mention.id => { platform: "GitHub", metric_name: "stars", metric_value: "30", tier: "good" },
        second.id => { platform: "Hacker News", metric_name: "points", metric_value: "120", tier: "great" }
      }
    }
    assert_redirected_to admin_virality_reviews_path(queue: "pending")

    decisions = ViralityDecision.where(project_mention: [ @mention, second ])
    assert_equal({ @mention.id => "good", second.id => "great" }, decisions.to_h { |decision| [ decision.project_mention_id, decision.tier ] })
    assert_equal [ "scheduled" ], decisions.map(&:status).uniq
    assert_equal [ "Nice reach" ], decisions.map(&:reason).uniq
    assert_equal ProjectMention::ELIGIBILITY_CHECKS, second.reload.review_checklist
    assert_equal 120, second.metric_value
  end

  test "batch rejection covers repeat submissions without their own evidence" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in @user
    repeat = @mention.project.mentions.create!(url: @mention.url)

    post batch_admin_virality_reviews_path, params: {
      project_id: @mention.project_id, mention_ids: [ @mention.id, repeat.id ], operation: "reject", reason: "Seems like a duplicate!",
      evidence: { @mention.id => { platform: "GitHub", metric_name: "stars", metric_value: "3" } }
    }

    assert_equal 2, ViralityDecision.where(project_mention: [ @mention, repeat ], action: "reject").count
    assert_equal "GitHub", ViralityDecision.find_by!(project_mention: repeat).evidence["platform"]
  end

  test "batch review is all or nothing and names the mention that failed" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in @user
    second = project_mentions(:virality_second)

    post batch_admin_virality_reviews_path, params: {
      project_id: @mention.project_id, mention_ids: [ @mention.id, second.id ], operation: "approve",
      review_checklist: ProjectMention::ELIGIBILITY_CHECKS, internal_note: "batch note",
      evidence: {
        @mention.id => { platform: "GitHub", metric_name: "stars", metric_value: "30", tier: "good" },
        second.id => { platform: "GitHub", metric_name: "stars", metric_value: "2", tier: "good" }
      }
    }

    assert_redirected_to admin_virality_reviews_path(queue: "pending", project_id: @mention.project_id)
    assert_match "Mention ##{second.id}", flash[:alert]
    assert_empty ViralityDecision.where(project_mention: [ @mention, second ])
    assert_nil @mention.reload.internal_notes
  end

  test "batch hold and release move the selected mentions together" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in @user
    second = project_mentions(:virality_second)
    params = { project_id: @mention.project_id, mention_ids: [ @mention.id, second.id ] }

    post batch_admin_virality_reviews_path, params: params.merge(operation: "hold", internal_note: "Asked about paid promotion")
    assert [ @mention, second ].all? { |mention| mention.reload.on_hold_at? }
    assert_equal "Asked about paid promotion", second.internal_notes

    post batch_admin_virality_reviews_path, params: params.merge(operation: "release")
    assert [ @mention, second ].none? { |mention| mention.reload.on_hold_at? }
  end

  test "batch review is admin only and limited to the project's mentions" do
    @user.update!(granted_roles: [ "project_certifier" ])
    sign_in @user
    post batch_admin_virality_reviews_path, params: { project_id: @mention.project_id, mention_ids: [ @mention.id ], operation: "reject", reason: "x" }
    assert_response :forbidden

    @user.update!(granted_roles: [ "admin" ])
    other = projects(:two).mentions.create!(url: "https://github.com/other/repo")
    post batch_admin_virality_reviews_path, params: { project_id: @mention.project_id, mention_ids: [ other.id ], operation: "reject", reason: "x" }
    assert_equal "Select at least one mention", flash[:alert]
    assert_empty other.virality_decisions
  end
end
