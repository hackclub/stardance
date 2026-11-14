require "test_helper"

class Projects::MentionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:virality_bonus)
    @owner = users(:one)
    @project = projects(:one)
    @project.memberships.find_by!(user: @owner).update!(role: :owner)
    @approved = project_mentions(:virality_pending)
    @approved.update!(approved_at: Time.current, approved_tier: "great", reviewer_notes: "Well done! :)",
                      platform: "GitHub", metric_name: "stars", metric_value: 140)
    @pending = project_mentions(:virality_second)
    @pending.update!(proposed_action: "reject", reviewer_notes: "Unconfirmed imported reply")
  end

  teardown { Flipper.disable(:virality_bonus) }

  test "members see each mention's status and the reply once it is decided" do
    sign_in @owner
    get project_mentions_path(@project)

    assert_response :success
    assert_select ".project-mentions__item", 2
    assert_select ".status-pill--approved", "Approved · Great"
    assert_select ".status-pill--pending", "Pending review"
    assert_select ".project-mentions__reply", /Well done! :\)/
    assert_select ".project-mentions__metric", "140 stars on GitHub"
    assert_no_match "Unconfirmed imported reply", response.body
  end

  test "people outside the project cannot see its mentions" do
    sign_in users(:two)
    get project_mentions_path(@project)
    assert_response :forbidden
  end

  test "submitting sends members to the list" do
    sign_in @owner
    post project_mentions_path(@project), params: { project_mention: { url: "https://news.ycombinator.com/item?id=1" } }
    assert_redirected_to project_mentions_path(@project)
  end
end
