require "test_helper"

class UsersProfileActivityTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user(slack_id: "U_PA_ADMIN", display_name: "pa_admin", verified: true)
    @admin.grant_role!(:admin)
    @owner = create_user(slack_id: "U_PA_OWNER", display_name: "pa_owner", verified: true)

    @project = Project.create!(title: "Starry Project", marked_fire_at: Time.current, marked_fire_by: @admin)
    @project.memberships.create!(user: @owner, role: :owner)
    Post.create!(project: @project, user: @admin, postable: Post::FireEvent.create!)
  end

  test "super star post is not shown on the granting admin's profile" do
    sign_in @admin

    get user_path(@admin)

    assert_response :success
    assert_select ".feed-post-card--fire", 0
  end

  test "super star post is still shown on the project" do
    sign_in @admin

    get project_path(@project)

    assert_response :success
    assert_select ".feed-post-card--fire", 1
  end
end
