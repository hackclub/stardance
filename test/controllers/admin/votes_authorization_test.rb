require "test_helper"

class Admin::VotesAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("admin", :admin)
    @helper = create_user("helper", :helper)
    @fraud_reviewer = create_user("fraud", :fraud_dept)
    @target_user = create_user("target")
    @project = Project.create!(title: "Vote authorization project")
  end

  test "admin can view project and user votes" do
    sign_in @admin

    get votes_admin_project_path(@project)
    assert_response :success

    get admin_user_votes_path(@target_user)
    assert_response :success
  end

  test "support cannot view project or user votes" do
    assert_vote_pages_forbidden_for @helper
  end

  test "fraud staff cannot view project or user votes" do
    assert_vote_pages_forbidden_for @fraud_reviewer
  end

  private

  def create_user(label, role = nil)
    user = User.create!(
      slack_id: "U_VOTES_#{label.upcase}",
      display_name: "votes_#{label}",
      email: "votes_#{label}@example.test"
    )
    user.grant_role!(role) if role
    user
  end

  def assert_vote_pages_forbidden_for(user)
    sign_in user

    get votes_admin_project_path(@project)
    assert_response :forbidden

    get admin_user_votes_path(@target_user)
    assert_response :forbidden
  end
end
