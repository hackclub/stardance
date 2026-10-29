require "test_helper"

class OneTime::BackfillHackatimeProjectSnapshotsJobTest < ActiveJob::TestCase
  setup do
    @owner = User.create!(slack_id: "U_SNAPSHOT_OWNER", display_name: "snapshot_owner", email: "snapshot_owner@example.test")
    @project = Project.create!(title: "Comma project", description: "uses my,project")
    @project.memberships.create!(user: @owner, role: :owner)
    User::HackatimeProject.create!(user: @owner, project: @project, name: "my,project")
  end

  test "fills the names snapshot without touching credited time" do
    devlog = create_legacy_devlog("my,project", 9401)
    project_seconds = @project.reload.duration_seconds

    result = OneTime::BackfillHackatimeProjectSnapshotsJob.perform_now

    assert_equal 1, result[:updated]
    assert_equal [ "my,project" ], devlog.reload.hackatime_project_names_snapshot
    assert_equal 9401, devlog.duration_seconds
    assert_equal project_seconds, @project.reload.duration_seconds
    assert_equal 0, OneTime::BackfillHackatimeProjectSnapshotsJob.perform_now[:updated]
  end

  test "leaves an ambiguous legacy snapshot unresolved" do
    User::HackatimeProject.create!(user: @owner, name: "my")
    User::HackatimeProject.create!(user: @owner, name: "project")
    devlog = create_legacy_devlog("my,project", 3600)

    result = OneTime::BackfillHackatimeProjectSnapshotsJob.perform_now

    assert_equal 1, result[:unresolved]
    assert_nil devlog.reload.hackatime_project_names_snapshot
    assert_equal 3600, devlog.duration_seconds
  end

  private

  def create_legacy_devlog(snapshot, seconds)
    devlog = Post::Devlog.create!(body: "Legacy devlog", duration_seconds: seconds,
                                  hackatime_projects_key_snapshot: snapshot, uploading_attachments: true)
    Post.create!(project: @project, user: @owner, postable: devlog)
    devlog
  end
end
