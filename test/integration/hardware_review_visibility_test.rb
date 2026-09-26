require "test_helper"

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

    @nonmember = create_user(slack_id: "U_HRV_OTHER", display_name: "hrv-other")
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
    sign_in @owner
    assert review_visible?, "the project owner should see the review"
  end

  test "a reviewer always sees the review, even without the rollout flag" do
    reviewer = create_user(slack_id: "U_HRV_REV", display_name: "hrv-rev")
    reviewer.grant_role!(:project_certifier)
    sign_in reviewer
    assert review_visible?, "a reviewer should always see the review history"
  end
end
