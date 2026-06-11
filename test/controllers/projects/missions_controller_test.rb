require "test_helper"

class Projects::MissionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email: "mission-owner-#{SecureRandom.hex(4)}@example.test",
                          display_name: "mission-owner-#{SecureRandom.hex(4)}",
                          slack_id: "U#{SecureRandom.hex(8)}")
    @project = Project.create!(title: "Mission Switch Test")
    @project.memberships.create!(user: @owner, role: :owner)

    @mission = create_mission
    @follow_up = create_mission(prerequisite: @mission)
    @project.mission_attachments.create!(mission: @mission)
  end

  test "switches a shipped project to a follow-up mission" do
    ship_to_mission!(@project, @owner, @mission, status: "approved")
    sign_in @owner

    post project_mission_path(@project), params: { mission_slug: @follow_up.slug }

    assert_redirected_to project_path(@project)
    assert_equal @follow_up, @project.reload.current_mission
    assert @project.mission_attachments.find_by(mission: @mission).detached_at.present?
  end

  test "switches a draft project straight to another mission" do
    other = create_mission
    sign_in @owner

    post project_mission_path(@project), params: { mission_slug: other.slug }

    assert_redirected_to project_path(@project)
    assert_equal other, @project.reload.current_mission
    assert @project.mission_attachments.find_by(mission: @mission).detached_at.present?
  end

  test "refuses to detach a mission the project shipped to" do
    ship_to_mission!(@project, @owner, @mission, status: "approved")
    sign_in @owner

    delete project_mission_path(@project)

    assert_redirected_to project_path(@project)
    assert_match(/locked in/, flash[:alert])
    assert_equal @mission, @project.reload.current_mission
  end

  test "follow_up_targets_for classifies ready and awaiting follow-ups" do
    submission = ship_to_mission!(@project, @owner, @mission)

    targets = @project.reload.follow_up_targets_for(@owner)
    assert_empty targets[:ready]
    assert_equal [ @follow_up ], targets[:awaiting]

    submission.update_column(:status, "approved")
    targets = Project.find(@project.id).follow_up_targets_for(User.find(@owner.id))
    assert_equal [ @follow_up ], targets[:ready]
    assert_empty targets[:awaiting]
  end

  test "original mission still recognizes the project after switching to a follow-up" do
    ship_to_mission!(@project, @owner, @mission, status: "approved")
    sign_in @owner
    post project_mission_path(@project), params: { mission_slug: @follow_up.slug }

    assert_equal @project, @owner.active_project_for_mission(@mission)
    assert_includes @mission.showcase_projects.to_a, @project

    get mission_path(@mission.slug)

    assert_response :success
    assert_select "a[href=?]", project_path(@project), text: "View my project"
  end

  test "guide section completions are frozen after switching away" do
    ship_to_mission!(@project, @owner, @mission, status: "approved")
    step = @mission.steps.create!(title: "Step 1", position: 0)
    completion = @project.mission_section_completions.create!(
      mission_step_id: step.id, mission_id: @mission.id, completed_at: Time.current
    )
    sign_in @owner
    post project_mission_path(@project), params: { mission_slug: @follow_up.slug }

    delete project_mission_section_completion_path(@project, step.id)

    assert_response :unprocessable_entity
    assert Mission::SectionCompletion.exists?(completion.id)
  end

  test "detaching a follow-up mission falls back to the previously shipped mission" do
    ship_to_mission!(@project, @owner, @mission, status: "approved")
    sign_in @owner
    post project_mission_path(@project), params: { mission_slug: @follow_up.slug }

    delete project_mission_path(@project)

    assert_redirected_to project_path(@project)
    assert_equal @mission, @project.reload.current_mission
  end

  test "detaching without prior ships leaves the project mission-less" do
    sign_in @owner

    delete project_mission_path(@project)

    assert_redirected_to project_path(@project)
    assert_nil @project.reload.current_mission
  end

  test "does not switch while the prerequisite submission is still unapproved" do
    ship_to_mission!(@project, @owner, @mission)
    sign_in @owner

    post project_mission_path(@project), params: { mission_slug: @follow_up.slug }

    assert_redirected_to project_path(@project)
    assert_match(/Complete/, flash[:alert])
    assert_equal @mission, @project.reload.current_mission
  end

  test "does not switch a shipped project to an unrelated mission" do
    ship_to_mission!(@project, @owner, @mission, status: "approved")
    unrelated = create_mission
    sign_in @owner

    post project_mission_path(@project), params: { mission_slug: unrelated.slug }

    assert_redirected_to project_path(@project)
    assert_match(/already shipped/, flash[:alert])
    assert_equal @mission, @project.reload.current_mission
  end
end
