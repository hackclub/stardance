require "test_helper"

class ProjectMagicTest < ActiveSupport::TestCase
  setup do
    @admin = create_user(slack_id: "U_PM_ADMIN", display_name: "pm_admin", verified: true)
    @admin.grant_role!(:admin)
    @owner = create_user(slack_id: "U_PM_OWNER", display_name: "pm_owner", verified: true)

    @project = Project.create!(title: "Starry Project")
    @project.memberships.create!(user: @owner, role: :owner)
    @magic = Project::Magic.new(@project)
  end

  test "revoking removes the super star post from the project" do
    assert @magic.grant(@admin)
    assert_equal 1, @project.posts.of_fire_events.count

    assert @magic.revoke(@admin)

    assert_equal 0, @project.posts.of_fire_events.count
    assert_equal 0, Post::FireEvent.count
  end

  test "re-granting after a revoke leaves a single super star post" do
    @magic.grant(@admin)
    @magic.revoke(@admin)
    @magic.grant(@admin)

    assert_equal 1, @project.posts.of_fire_events.count
  end
end
