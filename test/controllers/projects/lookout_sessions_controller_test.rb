require "test_helper"

class Projects::LookoutSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:hardware_flow)
    @owner = create_user(slack_id: "U_LS_OWNER", display_name: "ls_owner")
    # A linked Hackatime account is required to start a session. insert_all skips
    # the after_commit sync (no network) and the access_token presence validation.
    User::Identity.insert_all([
      { user_id: @owner.id, provider: "hackatime", uid: "ht-ls-owner", created_at: Time.current, updated_at: Time.current }
    ])
    @stranger = create_user(slack_id: "U_LS_STRANGER", display_name: "ls_stranger")
    @project = Project.create!(title: "Robot arm", hardware_stage: "build")
    @project.memberships.create!(user: @owner, role: :owner)
  end

  test "member can create a session and gets back the recorder url" do
    sign_in @owner

    created = { token: "tok-abc", sessionId: "sid-1", sessionUrl: "https://lookout.test/session?token=tok-abc" }
    LookoutService.stub(:create_session, created) do
      assert_difference -> { @project.lookout_sessions.count }, 1 do
        post project_lookout_sessions_path(@project)
      end
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "tok-abc", body["token"]
    assert_includes body["session_url"], "tok-abc"
    assert_equal "pending", body["status"]
  end

  test "create responds 503 when Lookout is unavailable" do
    sign_in @owner

    LookoutService.stub(:create_session, nil) do
      assert_no_difference -> { LookoutSession.count } do
        post project_lookout_sessions_path(@project)
      end
    end

    assert_response :service_unavailable
  end

  test "non-member cannot create a session" do
    sign_in @stranger

    LookoutService.stub(:create_session, { token: "nope" }) do
      assert_no_difference -> { LookoutSession.count } do
        post project_lookout_sessions_path(@project)
      end
    end
  end

  test "create is rejected until the user links a Hackatime account" do
    nolinker = create_user(slack_id: "U_LS_NOLINK", display_name: "ls_nolink")
    project = Project.create!(title: "Unlinked rig", hardware_stage: "build")
    project.memberships.create!(user: nolinker, role: :owner)
    sign_in nolinker

    LookoutService.stub(:create_session, { token: "should-not-be-called" }) do
      assert_no_difference -> { LookoutSession.count } do
        post project_lookout_sessions_path(project)
      end
    end

    assert_response :unprocessable_entity
    assert_equal "Link your Hackatime account before recording a timelapse.", JSON.parse(response.body)["error"]
  end

  test "status lists only the current member's sessions" do
    @project.lookout_sessions.create!(user: @owner, token: "mine", status: "complete", duration_seconds: 1800)
    other = create_user(slack_id: "U_LS_OTHER", display_name: "ls_other")
    @project.lookout_sessions.create!(user: other, token: "theirs", status: "complete")

    sign_in @owner
    get status_project_lookout_sessions_path(@project)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ "mine" ], body.map { |s| s["token"] }
  end

  test "show syncs status, duration, and video from Lookout (camelCase)" do
    session = @project.lookout_sessions.create!(user: @owner, token: "tok-show", status: "active", duration_seconds: 60)
    sign_in @owner

    remote = { status: "complete", trackedSeconds: 3600, videoUrl: "https://lookout.test/v/x" }
    LookoutService.stub(:fetch_session, remote) do
      get project_lookout_session_path(@project, session)
    end

    assert_response :success
    session.reload
    assert_equal "complete", session.status
    assert_equal 3600, session.duration_seconds
    assert_equal "https://lookout.test/v/x", session.recording_url
  end

  test "syncing a session to complete does not auto-forward heartbeats" do
    # Forwarding is user-driven now (the recorder's destination step), so simply
    # observing a session reach "complete" must not push anything to Hackatime.
    session = @project.lookout_sessions.create!(user: @owner, token: "tok-sync", status: "active")
    sign_in @owner

    enqueued = []
    ForwardLookoutHeartbeatsJob.stub(:perform_later, ->(*args) { enqueued << args }) do
      LookoutService.stub(:fetch_session, { status: "complete", trackedSeconds: 120, videoUrl: "https://lookout.test/v/y" }) do
        get project_lookout_session_path(@project, session)
      end
    end

    assert_empty enqueued
    session.reload
    assert_equal "complete", session.status
    assert_equal "https://lookout.test/v/y", session.recording_url
  end

  test "forward_heartbeats sends to the chosen Hackatime project and reports success" do
    session = @project.lookout_sessions.create!(user: @owner, token: "tok-fwd", status: "stopped")
    sign_in @owner

    received = []
    forward = lambda do |sess, project_name:|
      received << [ sess.id, project_name ]
      LookoutHeartbeatForwarder::Result.new(ok: true, error: nil, count: 3)
    end

    LookoutHeartbeatForwarder.stub(:call, forward) do
      post forward_heartbeats_project_lookout_session_path(@project, session), params: { project_name: "My HT Project" }
    end

    assert_response :success
    assert_equal [ [ session.id, "My HT Project" ] ], received
    body = JSON.parse(response.body)
    assert_equal true, body["ok"]
    assert_equal "My HT Project", body["project"]
    assert_equal 3, body["heartbeats"]
  end

  test "forward_heartbeats returns the failure reason when the send doesn't go through" do
    session = @project.lookout_sessions.create!(user: @owner, token: "tok-fwd-fail", status: "stopped")
    sign_in @owner

    failure = LookoutHeartbeatForwarder::Result.new(
      ok: false,
      error: "Hackatime didn't accept your time. Please try again in a moment.",
      count: 0
    )

    LookoutHeartbeatForwarder.stub(:call, failure) do
      post forward_heartbeats_project_lookout_session_path(@project, session), params: { project_name: "My HT Project" }
    end

    assert_response :unprocessable_entity
    assert_equal "Hackatime didn't accept your time. Please try again in a moment.",
                 JSON.parse(response.body)["error"]
  end

  test "forward_heartbeats rejects a blank project name without trying to send" do
    session = @project.lookout_sessions.create!(user: @owner, token: "tok-fwd-blank", status: "stopped")
    sign_in @owner

    called = false
    LookoutHeartbeatForwarder.stub(:call, ->(*args, **kwargs) { called = true }) do
      post forward_heartbeats_project_lookout_session_path(@project, session), params: { project_name: "  " }
    end

    assert_response :unprocessable_entity
    assert_not called
  end

  test "forward_heartbeats rejects an excluded project name without trying to send" do
    session = @project.lookout_sessions.create!(user: @owner, token: "tok-fwd-excl", status: "stopped")
    sign_in @owner

    called = false
    LookoutHeartbeatForwarder.stub(:call, ->(*args, **kwargs) { called = true }) do
      post forward_heartbeats_project_lookout_session_path(@project, session), params: { project_name: User::HackatimeProject::EXCLUDED_NAMES.first }
    end

    assert_response :unprocessable_entity
    assert_not called
  end

  test "set_mode stores a valid recording mode" do
    session = @project.lookout_sessions.create!(user: @owner, token: "tok-mode", status: "pending")
    sign_in @owner

    post set_mode_project_lookout_session_path(@project, session), params: { mode: "camera" }

    assert_response :ok
    assert_equal "camera", session.reload.mode
  end

  test "set_mode rejects an unknown recording mode" do
    session = @project.lookout_sessions.create!(user: @owner, token: "tok-mode2", status: "pending")
    sign_in @owner

    post set_mode_project_lookout_session_path(@project, session), params: { mode: "vr" }

    assert_response :unprocessable_entity
    assert_nil session.reload.mode
  end

  test "record renders the Desktop/Browser/Camera chooser for a member" do
    session = @project.lookout_sessions.create!(user: @owner, token: "tok-rec", status: "pending")
    sign_in @owner

    get record_project_lookout_session_path(@project, session)

    assert_response :success
    assert_select "main.lookout-rec[data-controller='lookout-capture']"
    assert_select "[data-lookout-capture-token-value=?]", "tok-rec"
    assert_select ".lookout-rec__option", 3
    assert_select ".lookout-rec__option-name", text: "Desktop"
    assert_select ".lookout-rec__option-name", text: "Browser"
    assert_select ".lookout-rec__option-name", text: "Camera"
  end

  test "record renders the Hackatime destination chooser listing existing projects" do
    @owner.hackatime_projects.create!(name: "Existing HT Project")
    session = @project.lookout_sessions.create!(user: @owner, token: "tok-dest", status: "pending")
    sign_in @owner

    get record_project_lookout_session_path(@project, session)

    assert_response :success
    assert_select ".lookout-rec__destination"
    # The three destinations: existing / new / don't send.
    assert_select "input[name='lookout-dest']", 3
    assert_select ".lookout-rec__dest-select option", text: "Existing HT Project"
    # New-project field defaults to this project's recorder name.
    assert_select ".lookout-rec__dest-input[value=?]", @project.hackatime_recorder_name
  end

  test "record groups the project's linked Hackatime projects first and defaults to one" do
    @owner.hackatime_projects.create!(name: "Unrelated HT Project")
    @owner.hackatime_projects.create!(name: "Arm firmware", project: @project)
    @owner.hackatime_projects.create!(name: "Arm enclosure", project: @project)
    session = @project.lookout_sessions.create!(user: @owner, token: "tok-linked", status: "pending")
    sign_in @owner

    get record_project_lookout_session_path(@project, session)

    assert_response :success
    # Both linked projects are grouped first under "Linked to this project".
    assert_select "optgroup[label='Linked to this project'] option", count: 2
    assert_select "optgroup[label='Linked to this project'] option", text: "Arm firmware"
    assert_select "optgroup[label='Linked to this project'] option", text: "Arm enclosure"
    # The unrelated one sits under the other group.
    assert_select "optgroup[label='Your other Hackatime projects'] option", text: "Unrelated HT Project"
    # Exactly one option is pre-selected, and it's one of the linked ones.
    assert_select ".lookout-rec__dest-select option[selected]", 1
    assert_select "option[selected][value=?]", "Arm enclosure"
  end

  test "stop marks the session stopped" do
    session = @project.lookout_sessions.create!(user: @owner, token: "tok-stop", status: "active")
    sign_in @owner

    LookoutService.stub(:stop_session, {}) do
      post stop_project_lookout_session_path(@project, session)
    end

    assert_response :success
    assert_equal "stopped", session.reload.status
  end
end
