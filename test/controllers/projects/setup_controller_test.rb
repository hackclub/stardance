require "test_helper"

class Projects::SetupControllerTest < ActionDispatch::IntegrationTest
  setup do
    @guest = User.create!(email: "setup_guest@example.com", display_name: "setup_guest")
    post onboarding_start_path, params: { email: @guest.email }
  end

  test "GET /projects/setup renders the idea step" do
    get projects_setup_path
    assert_response :success
    assert_select "h1", text: /Do you have an idea/
  end

  test "setup is closed once Stardance ends" do
    Project.stub(:shipping_closed?, true) do
      assert_no_difference "Project.count" do
        post projects_setup_submit_name_path, params: { title: "Late Project" }
      end
    end
    assert_redirected_to home_path
    assert_equal Project::CREATION_CLOSED_MESSAGE, flash[:alert]
  end

  test "POST submit_idea with yes routes to name step and does not create a project" do
    assert_no_difference "Project.count" do
      post projects_setup_submit_idea_path, params: { idea: "yes" }
    end
    assert_redirected_to projects_setup_name_path
  end

  test "POST submit_idea with no routes to missions step and does not create a project" do
    assert_no_difference "Project.count" do
      post projects_setup_submit_idea_path, params: { idea: "no" }
    end
    assert_redirected_to projects_setup_missions_path
  end

  test "POST submit_name creates a project with the user as owner and routes to link gate" do
    assert_difference "Project.count", 1 do
      post projects_setup_submit_name_path, params: { title: "Cosmic Sticky Notes", description: "tiny note-taking app" }
    end

    project = Project.order(:id).last
    assert_equal "Cosmic Sticky Notes", project.title
    assert_equal "tiny note-taking app", project.description
    assert_equal @guest.id, project.memberships.owner.first&.user_id
    assert_equal project.id, session[:setup_project_id]
    assert_redirected_to projects_setup_link_account_path
  end

  test "POST submit_name with blank title re-renders with alert" do
    assert_no_difference "Project.count" do
      post projects_setup_submit_name_path, params: { title: "  ", description: "x" }
    end
    assert_redirected_to projects_setup_name_path
  end

  test "POST submit_mission with figure_it_out_later creates a project with default title" do
    assert_difference "Project.count", 1 do
      post projects_setup_submit_mission_path, params: { figure_it_out_later: "1" }
    end
    project = Project.order(:id).last
    assert_equal Projects::SetupController::DEFAULT_PROJECT_TITLE, project.title
    assert_redirected_to projects_setup_link_account_path
  end

  test "GET /projects/setup/link_account stores return_to for HCA callback" do
    post projects_setup_submit_name_path, params: { title: "Test", description: "" }
    get projects_setup_link_account_path
    assert_response :success
    assert_equal projects_setup_welcome_path, session[:return_to]
  end

  test "GET /projects/setup/welcome bounces unlinked users back to link gate" do
    post projects_setup_submit_name_path, params: { title: "Test", description: "" }
    get projects_setup_welcome_path
    assert_redirected_to projects_setup_link_account_path
  end

  test "GET /projects/setup without session redirects unauthenticated visitors" do
    # Fresh request session — bypass the per-test `setup` login by using a fresh
    # integration session.
    open_session do |sess|
      sess.get projects_setup_path
      sess.assert_redirected_to root_path
    end
  end

  test "guest owner visiting the project show page is redirected to the link gate" do
    post projects_setup_submit_name_path, params: { title: "Mid-Setup", description: "" }
    project = Project.order(:id).last

    get project_path(project)
    assert_redirected_to projects_setup_link_account_path
    follow_redirect!
    assert_match(/Finish setting up your account/, flash[:alert].to_s + response.body.to_s)
  end

  test "HCA-linked owner viewing their own project is not redirected" do
    post projects_setup_submit_name_path, params: { title: "Mid-Setup", description: "" }
    project = Project.order(:id).last
    @guest.identities.create!(provider: "hack_club", uid: "hca_setup_guest")

    get project_path(project)
    assert_response :success
  end

  test "find_setup_project falls back to most recent draft when session is cleared" do
    post projects_setup_submit_name_path, params: { title: "Fallback Project", description: "" }
    project = Project.order(:id).last

    open_session do |sess|
      sess.post onboarding_start_path, params: { email: @guest.email }
      sess.get projects_setup_link_account_path
      sess.assert_response :success
      sess.assert_select "h1", text: /finish setting up your account/i
      sess.assert_equal project.id, sess.session[:setup_project_id]
    end
  end
end
