require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:hardware_flow)
    @owner = User.create!(slack_id: "U_PROJECT_OWNER", display_name: "owner", email: "owner@example.test")
    @owner.identities.create!(provider: "hack_club", uid: "hca_project_owner", access_token: "fake-token-project-owner")
    @viewer = User.create!(slack_id: "U_PROJECT_VIEWER", display_name: "viewer", email: "viewer@example.test")
    @project = Project.create!(title: "Forest Odyssey", description: "Explore a magical forest")
    @project.memberships.create!(user: @owner, role: :owner)
  end

  test "owner sees inline project editing form on show" do
    sign_in @owner

    get project_path(@project, editing: true)

    assert_response :success
    assert_select "form.project-show--editing[action=?]", project_path(@project)
    assert_select "input[name='project[title]'][value=?]", "Forest Odyssey"
    assert_select "textarea[name='project[description]']", text: "Explore a magical forest"
    assert_select "input[name='inline_project_show'][value='1']", 1
  end

  test "owner can update project from inline show form" do
    sign_in @owner

    patch project_path(@project), params: {
      inline_project_show: "1",
      project: {
        title: "Forest Odyssey DX",
        description: "A brighter forest",
        demo_url: "",
        repo_url: "",
        readme_url: "",
        ai_declaration: "Used AI to rubber-duck CSS."
      }
    }

    assert_redirected_to project_path(@project)
    @project.reload
    assert_equal "Forest Odyssey DX", @project.title
    assert_equal "A brighter forest", @project.description
    assert_equal "Used AI to rubber-duck CSS.", @project.ai_declaration
  end

  test "non-owner sees read-only project shell" do
    sign_in @viewer

    get project_path(@project)

    assert_response :success
    assert_select "form.project-show--editing", 0
    assert_select ".project-show__title", text: "Forest Odyssey"
  end

  test "owner of empty project sees the onboarding welcome prompting a Hackatime link" do
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select ".project-show__onboarding"
    assert_select "#project-show-onboarding-title", text: "Welcome to your new project!"
    # The redesigned onboarding replaced the discrete GitHub/Hackatime setup
    # cards with a single contextual message; an owner with no Hackatime link is
    # nudged to connect it.
    assert_select ".project-show__onboarding-header-body", text: /Link Hackatime to start tracking your time/
  end

  test "owner with hackatime identity does not see hackatime setup card" do
    User::Identity.insert_all([
      {
        user_id: @owner.id,
        provider: "hackatime",
        uid: "hackatime-owner",
        created_at: Time.current,
        updated_at: Time.current
      }
    ])
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select ".project-show__onboarding"
    assert_select ".project-show__onboarding", { text: /Set up hour tracking with Hackatime/, count: 0 }
    assert_select ".project-show__onboarding form[action='/auth/hackatime']", 0
  end

  test "project with an attached mission is not prompted to browse missions" do
    mission = Mission.create!(
      slug: "rusty-frontend",
      name: "Rusty Frontend",
      description: "Learn the basics of Rust while building frontend for a simple website."
    )
    @project.mission_attachments.create!(mission: mission)
    sign_in @owner

    get project_path(@project)

    assert_response :success
    # The onboarding mission card was retired in the project-show redesign;
    # missions now surface via the discover rail. A project that already has a
    # mission attached should not render the "browse missions" prompt.
    assert_select "#mission-browse-modal", 0
  end

  test "non-owner does not see owner onboarding" do
    sign_in @viewer

    get project_path(@project)

    assert_response :success
    assert_select ".project-show__onboarding", 0
  end

  test "project with existing post does not show onboarding block" do
    fire_event = Post::FireEvent.create!(body: "This project is already active.")
    Post.create!(project: @project, user: @owner, postable: fire_event)
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select ".project-show__onboarding", 0
  end

  test "non-owner cannot update project" do
    sign_in @viewer

    patch project_path(@project), params: {
      inline_project_show: "1",
      project: { title: "Not yours" }
    }

    assert_response :forbidden
    assert_equal "Forest Odyssey", @project.reload.title
  end

  test "creates a hardware project with a stage" do
    sign_in @owner

    assert_difference -> { Project.count }, 1 do
      post projects_path, params: { project: { title: "Soldering rig", hardware_stage: "design" } }
    end

    project = Project.order(:created_at).last
    assert_equal "design", project.hardware_stage
    assert project.hardware?
  end

  test "owner can switch the hardware stage from the edit form" do
    @project.update!(hardware_stage: "design")
    sign_in @owner

    patch project_path(@project), params: {
      inline_project_show: "1",
      project: { hardware_stage: "build" }
    }

    assert_redirected_to project_path(@project)
    assert_equal "build", @project.reload.hardware_stage
  end

  test "owner can convert a software project to hardware from the edit form" do
    sign_in @owner
    assert_not @project.hardware?

    # Picking Hardware + a stage submits the stage radio value, which wins over
    # the empty hidden hardware_stage field that's always present.
    patch project_path(@project), params: {
      inline_project_show: "1",
      project: { hardware_stage: "design" }
    }

    assert_redirected_to project_path(@project)
    @project.reload
    assert_equal "design", @project.hardware_stage
    assert @project.hardware?
  end

  test "owner can convert a hardware project back to software from the edit form" do
    @project.update!(hardware_stage: "build")
    sign_in @owner

    # Selecting Software disables the stage radios, so only the empty hidden
    # hardware_stage field submits — clearing the column (normalized to nil).
    patch project_path(@project), params: {
      inline_project_show: "1",
      project: { hardware_stage: "" }
    }

    assert_redirected_to project_path(@project)
    @project.reload
    assert_nil @project.hardware_stage
    assert_not @project.hardware?
  end

  test "owner sees the type toggle set to Hardware with the stage revealed on hardware projects" do
    @project.update!(hardware_stage: "build")
    sign_in @owner

    get project_path(@project, editing: true)

    assert_response :success
    # Hardware selected in the type toggle...
    assert_select "input[name='project_type_selector'][value='hardware'][checked]"
    # ...and the stage section is revealed (not hidden) with Build active + enabled.
    assert_select "[data-project-type-target='stageSection'][hidden]", 0
    assert_select "input[name='project[hardware_stage]'][value='build'][checked]"
    assert_select "input[name='project[hardware_stage]'][value='build'][disabled]", 0
  end

  test "software project edit form defaults to Software with the stage toggle hidden" do
    sign_in @owner

    get project_path(@project, editing: true)

    assert_response :success
    # Software is selected by default; Hardware is not.
    assert_select "input[name='project_type_selector'][value='software'][checked]"
    assert_select "input[name='project_type_selector'][value='hardware'][checked]", 0
    # The stage section is present but hidden, and its radios disabled so they
    # don't submit. An empty hidden field clears hardware_stage instead.
    assert_select "[data-project-type-target='stageSection'][hidden]"
    assert_select "input[name='project[hardware_stage]'][value='design'][disabled]"
    assert_select "input[name='project[hardware_stage]'][checked]", 0
    assert_select "input[type='hidden'][name='project[hardware_stage]']"
  end

  test "new project dialog offers the hardware project option and stage chooser" do
    sign_in @owner

    get new_project_path

    assert_response :success
    assert_select "button.project-creation__blank-btn--hardware"
    assert_select ".project-creation__stage-option", 2
    assert_select "input[name='project[hardware_stage]'][value='design']"
    assert_select "input[name='project[hardware_stage]'][value='build']"
  end

  test "hardware project record launcher is locked until a Hackatime account is linked" do
    @project.update!(hardware_stage: "build")
    sign_in @owner # has a hack_club identity but no Hackatime identity

    get project_path(@project)

    assert_response :success
    # Shown in the actions area, but disabled and without the recorder controller.
    assert_select ".project-show__actions button[aria-disabled='true']", text: /Record a timelapse/
    assert_select ".project-show__actions [data-controller~='lookout-recorder']", 0
  end

  test "hardware project record launcher is enabled once a Hackatime account is linked" do
    @project.update!(hardware_stage: "build")
    User::Identity.insert_all([
      { user_id: @owner.id, provider: "hackatime", uid: "ht-proj-owner", created_at: Time.current, updated_at: Time.current }
    ])
    sign_in @owner

    HackatimeService.stub(:fetch_stats, { projects: {}, banned: false }) do
      get project_path(@project)
    end

    assert_response :success
    assert_select ".project-show__actions [data-controller~='lookout-recorder'][data-lookout-recorder-create-url-value=?]",
                  project_lookout_sessions_path(@project)
    assert_select ".project-show__actions button[aria-disabled='true']", text: /Record a timelapse/, count: 0
  end

  test "software project page has no record-a-timelapse launcher" do
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select "button", text: /Record a timelapse/, count: 0
  end
end
