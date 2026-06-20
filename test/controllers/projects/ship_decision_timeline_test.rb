# frozen_string_literal: true

require "test_helper"

class Projects::ShipDecisionTimelineTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:week_1_release)

    @owner = create_user(slack_id: "U_VERDICT_OWNER", display_name: "verdictowner")
    @owner.update!(slack_id: nil)
    @reviewer = create_user(slack_id: "U_VERDICT_REVIEWER", display_name: "verdictreviewer")
    @outsider = create_user(slack_id: "U_VERDICT_OUTSIDER", display_name: "verdictoutsider")

    @project = Project.create!(
      title: "Visible Verdicts",
      description: "A project with review feedback",
      ship_status: "submitted"
    )
    @project.memberships.create!(user: @owner, role: :owner)

    review = @project.ship_reviews.create!(status: :pending)
    review.update!(status: :returned, feedback: "Tighten the demo video.", reviewer: @reviewer)
  end

  teardown do
    Flipper.disable(:week_1_release)
  end

  test "a verdict does not create any posts" do
    assert_not Post.where(project: @project).exists?
  end

  test "a project member sees the verdict card with feedback" do
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select ".ship-decision-card", 1
    assert_select ".ship-decision-card__feedback-body", text: /Tighten the demo video\./
  end

  test "a verdict suppresses the project onboarding banner even with no posts" do
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select ".ship-decision-card", 1
    assert_select ".project-show__onboarding", 0
  end

  test "an outsider does not see the verdict card" do
    sign_in @outsider

    get project_path(@project)

    assert_response :success
    assert_select ".ship-decision-card", 0
  end

  test "a signed-out viewer does not see the verdict card" do
    get project_path(@project)

    assert_response :success
    assert_select ".ship-decision-card", 0
  end

  test "the verdict card stays hidden while the release flag is off" do
    Flipper.disable(:week_1_release)
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select ".ship-decision-card", 0
  end
end
