require "test_helper"

class LookoutSessionTest < ActiveSupport::TestCase
  setup do
    @user = create_user(slack_id: "U_LS", display_name: "ls_user")
    @project = Project.create!(title: "Robot arm", hardware_stage: "build")
    @project.memberships.create!(user: @user, role: :owner)
  end

  test "valid with a token and known status" do
    session = LookoutSession.new(user: @user, project: @project, token: "tok-1", status: "pending")
    assert session.valid?
  end

  test "requires a token" do
    session = LookoutSession.new(user: @user, project: @project, status: "pending")
    assert_not session.valid?
  end

  test "rejects an unknown status" do
    session = LookoutSession.new(user: @user, project: @project, token: "tok-2", status: "bogus")
    assert_not session.valid?
  end

  test "rejects an unknown mode" do
    session = LookoutSession.new(user: @user, project: @project, token: "tok-3", status: "pending", mode: "vr")
    assert_not session.valid?
  end

  test "token is unique" do
    LookoutSession.create!(user: @user, project: @project, token: "dup", status: "pending")
    dup = LookoutSession.new(user: @user, project: @project, token: "dup", status: "pending")
    assert_not dup.valid?
  end

  test "attachable scope returns stopped and complete sessions" do
    LookoutSession.create!(user: @user, project: @project, token: "p", status: "pending")
    complete = LookoutSession.create!(user: @user, project: @project, token: "c", status: "complete")
    stopped = LookoutSession.create!(user: @user, project: @project, token: "s", status: "stopped")

    assert_equal [ complete.id, stopped.id ].sort, LookoutSession.attachable.pluck(:id).sort
  end

  test "hackatime_editor reflects the recording mode" do
    session = LookoutSession.new
    assert_equal "Lookout-Web", session.hackatime_editor # default when unset

    session.mode = "desktop"
    assert_equal "Lookout-Desktop", session.hackatime_editor
    session.mode = "web"
    assert_equal "Lookout-Web", session.hackatime_editor
    session.mode = "camera"
    assert_equal "Lookout-Camera", session.hackatime_editor
  end
end
