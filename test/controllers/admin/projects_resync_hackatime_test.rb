require "test_helper"

class Admin::ProjectsResyncHackatimeTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @owner = User.create!(slack_id: "U_RESYNC_OWNER", display_name: "resync_owner", email: "resync_owner@example.test")
    @owner.identities.create!(provider: "hackatime", uid: "HT_RESYNC", access_token: "token")
    @project = Project.create!(title: "Comma project", description: "uses my,project")
    @project.memberships.create!(user: @owner, role: :owner)
    User::HackatimeProject.create!(user: @owner, project: @project, name: "my,project")
    @admin = User.create!(slack_id: "U_RESYNC_ADMIN", display_name: "resync_admin", email: "resync_admin@example.test")
    @admin.grant_role!(:admin)
  end

  test "an admin queues an audited resync" do
    sign_in @admin

    assert_enqueued_with(job: Project::ResyncDevlogsFromHackatimeJob) do
      post resync_hackatime_admin_project_path(@project)
    end

    assert_redirected_to admin_project_path(@project)
    assert @project.versions.exists?(event: "hackatime_resync_requested", whodunnit: @admin.id.to_s)
  end

  test "a non-admin cannot queue a resync" do
    sign_in @owner

    assert_no_enqueued_jobs(only: Project::ResyncDevlogsFromHackatimeJob) do
      post resync_hackatime_admin_project_path(@project)
    end
  end

  test "the resync job recomputes comma-named devlog time and skips test devlogs" do
    devlog = create_devlog(duration_seconds: 9401, hackatime_projects_key_snapshot: "my,project")
    test_devlog = create_devlog(duration_seconds: 15.minutes.to_i, hackatime_projects_key_snapshot: "test")
    keys_seen = []
    fake_total = ->(_uid, keys, **) { keys_seen << keys; 2101 }

    HackatimeService.stub(:fetch_total_seconds_for_projects, fake_total) do
      Project::ResyncDevlogsFromHackatimeJob.perform_now(@project, requested_by_id: @admin.id)
    end

    assert_equal [ [ "my,project" ] ], keys_seen
    assert_equal 2101, devlog.reload.duration_seconds
    assert_equal [ "my,project" ], devlog.hackatime_project_names_snapshot
    assert_equal 15.minutes.to_i, test_devlog.reload.duration_seconds
    assert @project.versions.exists?(event: "hackatime_resync_completed", whodunnit: @admin.id.to_s)
  end

  private

  def create_devlog(**attrs)
    devlog = Post::Devlog.create!(body: "Devlog", uploading_attachments: true, **attrs)
    Post.create!(project: @project, user: @owner, postable: devlog)
    devlog
  end
end
