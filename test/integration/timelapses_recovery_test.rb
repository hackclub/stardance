require "test_helper"

class TimelapsesRecoveryTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @project = projects(:one)
    @pushed = LookoutSession.create!(user: @user, project: @project, token: "tok-done",
                                     status: "complete", duration_seconds: 600,
                                     started_at: Time.utc(2026, 7, 15, 12))
    @pending = LookoutSession.create!(user: @user, project: @project, token: "tok-todo",
                                      status: "complete", duration_seconds: 600,
                                      started_at: Time.utc(2026, 7, 16, 12))
    Rails.cache.clear
    sign_in @user
  end

  test "index marks already-pushed sessions done and offers to send the pending ones" do
    LookoutPushStatus.stub(:pushed_tokens, Set[@pushed.token]) do
      get my_timelapses_path
    end

    assert_response :success
    assert_select ".timelapses__status--done", text: "In Hackatime"
    # pending session gets a send form; the pushed one does not
    assert_select "form[action=?]", forward_heartbeats_project_lookout_session_path(@project, @pending)
    assert_select "form[action=?]", forward_heartbeats_project_lookout_session_path(@project, @pushed), count: 0
  end

  test "skips sessions whose project was soft-deleted instead of crashing the page" do
    orphan_project = projects(:two)
    orphan = LookoutSession.create!(user: @user, project: orphan_project, token: "tok-orphan",
                                    status: "complete", duration_seconds: 600,
                                    started_at: Time.utc(2026, 7, 17, 12))
    orphan_project.update_column(:deleted_at, Time.current)
    assert_nil orphan.reload.project, "guard assumes a soft-deleted project reads back as nil"

    LookoutPushStatus.stub(:pushed_tokens, Set.new) do
      get my_timelapses_path
    end

    assert_response :success
    assert_select "form[action=?]", forward_heartbeats_project_lookout_session_path(orphan_project, orphan), count: 0
    assert_select "form[action=?]", forward_heartbeats_project_lookout_session_path(@project, @pending)
  end

  test "one-click send forwards the session to Hackatime and returns to the list" do
    forwarded = nil
    ok = Struct.new(:ok, :error, :count) { def ok? = ok }.new(true, nil, 3)

    LookoutHeartbeatForwarder.stub(:call, ->(session, project_name:) { forwarded = [ session.id, project_name ]; ok }) do
      post forward_heartbeats_project_lookout_session_path(@project, @pending),
           params: { dest: "new", new_project_name: @project.hackatime_recorder_name }
    end

    assert_redirected_to my_timelapses_path
    assert_equal [ @pending.id, @project.hackatime_recorder_name ], forwarded
  end

  test "failed send returns to the finalize page with the error" do
    failed = Struct.new(:ok, :error, :count) { def ok? = ok }.new(false, "Hackatime didn't accept your time.", 0)

    LookoutHeartbeatForwarder.stub(:call, ->(*, **) { failed }) do
      post forward_heartbeats_project_lookout_session_path(@project, @pending),
           params: { dest: "new", new_project_name: @project.hackatime_recorder_name }
    end

    assert_redirected_to finalize_project_lookout_session_path(@project, @pending)
    assert_equal "Hackatime didn't accept your time.", flash[:alert]
  end
end
