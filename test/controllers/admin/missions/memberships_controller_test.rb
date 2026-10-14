require "test_helper"

class Admin::Missions::MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user(slack_id: "U_MEM_ADMIN", display_name: "mem-admin")
    @admin.grant_role!(:admin)
    @reviewer = create_user(slack_id: "U_MEM_REVIEWER", display_name: "Nova_Reviewer")
    @mission = create_mission
    sign_in @admin
  end

  test "a reviewer can be added by username, with or without @, or by profile link" do
    [ "Nova_Reviewer", "@nova_reviewer", "https://stardance.hackclub.com/@Nova_Reviewer" ].each do |query|
      @mission.memberships.reviewer_role.delete_all
      add_reviewer(query)
      assert @mission.memberships.reviewer_role.exists?(user: @reviewer), "expected #{query.inspect} to find the user"
      assert_equal "Nova_Reviewer added as reviewer.", flash[:reviewers_notice]
    end
  end

  test "a reviewer can still be added by user ID or Slack ID" do
    add_reviewer(@reviewer.id.to_s)
    assert @mission.memberships.reviewer_role.exists?(user: @reviewer)

    @mission.memberships.reviewer_role.delete_all
    add_reviewer("U_MEM_REVIEWER")
    assert @mission.memberships.reviewer_role.exists?(user: @reviewer)
  end

  test "a reviewer can be added by email, ignoring case" do
    @reviewer.update!(email: "nova.reviewer@example.test")
    add_reviewer("Nova.Reviewer@Example.test")
    assert @mission.memberships.reviewer_role.exists?(user: @reviewer)
    assert_equal "Nova_Reviewer added as reviewer.", flash[:reviewers_notice]
  end

  test "a failed add shows its reason inside the reviewers frame" do
    add_reviewer("nobody-by-this-name")
    assert_match(/No user found for "nobody-by-this-name"/, flash[:reviewers_alert])
    assert_nil flash[:alert]

    follow_redirect!
    assert_select "turbo-frame#admin-mission-edit-reviewers .admin-mission-edit__message--alert",
                  text: /No user found/

    add_reviewer("Nova_Reviewer")
    add_reviewer("Nova_Reviewer")
    assert_equal "Nova_Reviewer is already a reviewer.", flash[:reviewers_alert]
    assert_equal 1, @mission.memberships.reviewer_role.where(user: @reviewer).count
  end

  test "removing a reviewer reports inside the frame" do
    membership = @mission.memberships.create!(user: @reviewer, role: :reviewer)
    delete admin_mission_membership_path(@mission.slug, membership)
    assert_equal "Reviewer removed.", flash[:reviewers_notice]
  end

  test "owner changes keep using the page-level flash" do
    post admin_mission_memberships_path(@mission.slug),
         params: { mission_membership: { user_id: "nova_reviewer", role: "owner" } }
    assert @mission.memberships.owner_role.exists?(user: @reviewer)
    assert_equal "Nova_Reviewer added as owner.", flash[:notice]
  end

  private

  def add_reviewer(query)
    post admin_mission_memberships_path(@mission.slug),
         params: { mission_membership: { user_id: query, role: "reviewer" } }
    assert_redirected_to edit_admin_mission_path(@mission.slug)
  end
end
