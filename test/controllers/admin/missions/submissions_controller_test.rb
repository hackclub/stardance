require "test_helper"

class Admin::Missions::SubmissionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @reviewer = User.create!(email: "reviewer-#{SecureRandom.hex(4)}@example.test",
                             display_name: "reviewer-#{SecureRandom.hex(4)}",
                             slack_id: "U#{SecureRandom.hex(8)}",
                             granted_roles: [ "mission_reviewer" ])
    @builder = User.create!(email: "builder-#{SecureRandom.hex(4)}@example.test",
                            display_name: "builder-#{SecureRandom.hex(4)}",
                            slack_id: "U#{SecureRandom.hex(8)}")
    @project = Project.create!(title: "Queue Test Project")
    @project.memberships.create!(user: @builder, role: :owner)
    @mission = create_mission
    @project.mission_attachments.create!(mission: @mission)
    @submission = ship_to_mission!(@project, @builder, @mission, status: "pending")
  end

  test "reviewer walks the queue: index, next claims oldest, approve advances" do
    sign_in @reviewer

    get admin_mission_submissions_path(@mission.slug)
    assert_response :success

    get next_admin_mission_submissions_path(@mission.slug)
    assert_redirected_to admin_mission_submission_path(@mission.slug, @submission)
    assert_equal @reviewer.id, @submission.reload.reviewed_by_id

    patch admin_mission_submission_path(@mission.slug, @submission),
          params: { mission_submission: { status: "approved" } }
    assert_redirected_to next_admin_mission_submissions_path(@mission.slug)
    assert @submission.reload.approved?
    assert_equal 1, Mission::Submission.reviewed_today(@reviewer, mission: @mission)
  end

  test "the review page lists decided mission reviews on the same project" do
    earlier_mission = create_mission
    earlier = ship_to_mission!(@project, @builder, earlier_mission, status: "rejected")
    earlier.update!(reviewed_by: @reviewer, reviewed_at: 1.day.ago,
                    rejection_message: "Needs a real README")

    sign_in @reviewer
    get admin_mission_submission_path(@mission.slug, @submission)

    assert_response :success
    assert_select ".review-history__item", 1
    assert_select ".review-history__mission", text: earlier_mission.name
    assert_select ".review-history__feedback", text: /Needs a real README/
    assert_select ".review-history__link[href=?]",
                  admin_mission_submission_path(earlier_mission.slug, earlier)
  end

  # The common loop: the builder asks for a re-review, which reuses the same ship
  # event and wipes the verdict off the row. Without reading it back from
  # PaperTrail the next reviewer sees no sign this was already knocked back.
  test "the review page surfaces a verdict a re-review request erased" do
    sign_in @reviewer
    Mission::Submission.atomic_claim!(@submission.id, @reviewer)
    patch admin_mission_submission_path(@mission.slug, @submission),
          params: { mission_submission: { status: "rejected", feedback: "README is a stub." } }
    assert @submission.reload.rejected?

    sign_in @builder
    post project_mission_resubmission_path(@project)

    @submission.reload
    assert @submission.pending?, "the re-review request should send it back to the queue"
    assert_nil @submission.rejection_message, "the controller is expected to wipe the verdict"
    assert_nil @submission.reviewed_by_id

    sign_in @reviewer
    get admin_mission_submission_path(@mission.slug, @submission)

    assert_response :success
    assert_select ".review-history__item", 1
    assert_select ".review-history__feedback", text: /README is a stub\./
    assert_select ".review-history__meta", text: /#{@reviewer.display_name}/
    # It is this submission's own past, so there is nowhere else to link.
    assert_select ".review-history__link", count: 0
  end

  test "the review page leaves the submission being reviewed out of its own history" do
    @submission.update!(reviewed_by: @reviewer, reviewed_at: 1.hour.ago)
    @submission.update_column(:status, "approved")

    sign_in @reviewer
    get admin_mission_submission_path(@mission.slug, @submission)

    assert_response :success
    assert_select ".review-history__item", 0
    assert_select ".review-history__empty"
  end

  test "rejecting without feedback bounces back" do
    sign_in @reviewer
    Mission::Submission.atomic_claim!(@submission.id, @reviewer)

    patch admin_mission_submission_path(@mission.slug, @submission),
          params: { mission_submission: { status: "rejected", feedback: "" } }

    assert_redirected_to admin_mission_submission_path(@mission.slug, @submission)
    assert @submission.reload.pending?
  end

  test "plain reject leaves the project attached to the mission" do
    sign_in @reviewer
    Mission::Submission.atomic_claim!(@submission.id, @reviewer)

    patch admin_mission_submission_path(@mission.slug, @submission),
          params: { mission_submission: { status: "rejected", feedback: "Needs work" } }

    assert_redirected_to next_admin_mission_submissions_path(@mission.slug)
    assert @submission.reload.rejected?
    assert_equal @mission, @project.reload.current_mission
  end

  test "reject and detach frees the project from the mission" do
    sign_in @reviewer
    Mission::Submission.atomic_claim!(@submission.id, @reviewer)

    patch admin_mission_submission_path(@mission.slug, @submission),
          params: { mission_submission: { status: "rejected", feedback: "Needs work", detach_project: "1" } }

    assert_redirected_to next_admin_mission_submissions_path(@mission.slug)
    assert @submission.reload.rejected?
    assert_nil @project.reload.current_mission
  end

  test "detach flag is ignored when approving" do
    sign_in @reviewer
    Mission::Submission.atomic_claim!(@submission.id, @reviewer)

    patch admin_mission_submission_path(@mission.slug, @submission),
          params: { mission_submission: { status: "approved", detach_project: "1" } }

    assert @submission.reload.approved?
    assert_equal @mission, @project.reload.current_mission
  end

  test "claims are exclusive while fresh and stealable when expired" do
    other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.test",
                         display_name: "other-#{SecureRandom.hex(4)}",
                         slack_id: "U#{SecureRandom.hex(8)}",
                         granted_roles: [ "mission_reviewer" ])
    assert Mission::Submission.atomic_claim!(@submission.id, other)

    assert_nil Mission::Submission.atomic_claim!(@submission.id, @reviewer)

    @submission.reload.update_columns(claim_expires_at: 1.minute.ago)
    assert Mission::Submission.atomic_claim!(@submission.id, @reviewer)
  end

  test "the all-missions queue works without a specific mission" do
    sign_in @reviewer

    get admin_mission_submissions_path("all")
    assert_response :success

    get next_admin_mission_submissions_path("all")
    assert_redirected_to admin_mission_submission_path("all", @submission)
    assert_equal @reviewer.id, @submission.reload.reviewed_by_id
  end

  test "overview lists per-mission queue depth" do
    sign_in @reviewer
    get admin_mission_reviews_path
    assert_response :success
  end

  test "overview counts only hardware reviews the mission dash can hand out" do
    mission = create_mission
    mission.update!(hardware: true)
    live = hardware_project_for(mission)
    deleted = hardware_project_for(mission)
    Certification::Ship.create!(project: live, status: :pending)
    Certification::Ship.create!(project: deleted, status: :pending)
    deleted.soft_delete!

    sign_in @reviewer
    get admin_mission_reviews_path

    assert_response :success
    # The review on the soft-deleted project is unreachable from every queue.
    assert_includes response.body, "1 pending"
    assert_not_includes response.body, "2 pending"
  end

  test "overview only lists missions the user can review" do
    member = create_member
    other_mission = create_mission
    other_mission.memberships.create!(user: member, role: :reviewer)

    sign_in member
    get admin_mission_reviews_path
    assert_response :success
    assert_includes response.body, other_mission.name
    assert_not_includes response.body, @mission.name
  end

  test "helpers without memberships cannot browse the review queues" do
    helper = create_member(granted_roles: [ "helper" ])
    sign_in helper
    get admin_mission_reviews_path
    assert_not_equal 200, response.status
  end

  test "the all-missions queue never hands out inaccessible submissions" do
    member = create_member
    other_mission = create_mission
    other_mission.memberships.create!(user: member, role: :reviewer)

    sign_in member
    get next_admin_mission_submissions_path("all")
    assert_redirected_to admin_mission_submissions_path("all")
    assert_nil @submission.reload.reviewed_by_id
  end

  test "builders cannot reach the queue" do
    sign_in @builder
    get admin_mission_submissions_path(@mission.slug)
    assert_not_equal 200, response.status
  end

  private

  def create_member(granted_roles: [])
    User.create!(email: "member-#{SecureRandom.hex(4)}@example.test",
                 display_name: "member-#{SecureRandom.hex(4)}",
                 slack_id: "U#{SecureRandom.hex(8)}",
                 granted_roles: granted_roles)
  end

  def hardware_project_for(mission)
    project = Project.create!(title: "HW #{SecureRandom.hex(4)}")
    project.memberships.create!(user: @builder, role: :owner)
    project.update!(hardware_stage: "build")
    project.mission_attachments.create!(mission: mission)
    project
  end
end
