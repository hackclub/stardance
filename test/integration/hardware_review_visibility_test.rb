require "test_helper"

# Funding-review feedback is private to a project's members and admins by
# default. Reviewers can always see it, and the public_hardware_reviews flag
# opens it up to everyone. These pin who sees the review history on a project
# page (ProjectsController#hardware_review_history_visible?).
class HardwareReviewVisibilityTest < ActionDispatch::IntegrationTest
  FEEDBACK = "Please add a wiring diagram before we fund this.".freeze

  setup do
    @owner = create_user(slack_id: "U_HRV_OWNER", display_name: "hrv-owner", verified: true)
    @project = Project.create!(title: "Visible rover", hardware_stage: "design")
    @project.memberships.create!(user: @owner, role: :owner)

    devlog = Post::Devlog.new(body: "first log", duration_seconds: 3600, phase: "design")
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: @project, user: @owner, postable: devlog)

    review = @project.certification_funding_requests.new(
      user: @owner, complexity_tier: 2, requested_amount_cents: 5_000,
      status: :returned, feedback: FEEDBACK
    )
    review.save!(validate: false)
    review.update_columns(decided_at: 1.day.ago)

    # A logged-in non-member who is in the hardware rollout but has no claim on
    # this project - proves the member gate, not the rollout flag, is what hides
    # the review by default.
    @nonmember = create_user(slack_id: "U_HRV_OTHER", display_name: "hrv-other")
    Flipper.enable_actor(:hardware_flow, @nonmember)
  end

  teardown do
    Flipper.disable(:public_hardware_reviews)
    Flipper.disable_actor(:hardware_flow, @nonmember)
    Flipper.disable_actor(:hardware_flow, @owner)
  end

  def review_visible?
    get project_path(@project)
    assert_response :success
    response.body.include?(FEEDBACK)
  end

  test "a non-member does not see the review by default" do
    sign_in @nonmember
    assert_not review_visible?, "a non-member must not see funding-review feedback"
  end

  test "the project owner sees the review" do
    Flipper.enable_actor(:hardware_flow, @owner)
    sign_in @owner
    assert review_visible?, "the project owner should see the review"
  end

  test "public_hardware_reviews exposes the review to a non-member" do
    Flipper.enable(:public_hardware_reviews)
    sign_in @nonmember
    assert review_visible?, "the public flag should show the review to a non-member"
  end

  test "a reviewer always sees the review, even without the rollout flag" do
    reviewer = create_user(slack_id: "U_HRV_REV", display_name: "hrv-rev")
    reviewer.grant_role!(:project_certifier)
    sign_in reviewer
    assert review_visible?, "a reviewer should always see the review history"
  end
end
