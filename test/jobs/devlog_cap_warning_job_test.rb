require "test_helper"

class DevlogCapWarningJobTest < ActiveSupport::TestCase
  setup do
    @owner = create_user(slack_id: "U_CAP_OWNER", display_name: "cap_owner")
    @owner.identities.create!(provider: "hackatime", uid: "ht-cap-owner", access_token: "ht-secret")
    @project = Project.create!(title: "Cap Test", description: "Testing the devlog cap")
    @project.memberships.create!(user: @owner, role: :owner)
    User::HackatimeProject.create!(user: @owner, name: "cap-project", project: @project)
  end

  test "notifies the owner when un-devlogged time passes the warning threshold" do
    HackatimeService.stub(:fetch_total_seconds_for_projects, 9.hours.to_i) do
      assert_difference -> { Notifications::Projects::DevlogCapApproaching.count }, 1 do
        DevlogCapWarningJob.perform_now
      end
    end

    notification = Notifications::Projects::DevlogCapApproaching.last
    assert_equal @owner.id, notification.recipient_id
    assert_equal @project, notification.record
    assert_equal 9.hours.to_i, notification.params["unposted_seconds"]
    assert_equal "9h 0m", notification.unposted_time_text
  end

  test "notifies even when week_2_release is disabled for the owner" do
    Flipper.disable(:week_2_release)

    HackatimeService.stub(:fetch_total_seconds_for_projects, 9.hours.to_i) do
      assert_difference -> { Notifications::Projects::DevlogCapApproaching.count }, 1 do
        DevlogCapWarningJob.perform_now
      end
    end
  end

  test "does not notify below the warning threshold" do
    HackatimeService.stub(:fetch_total_seconds_for_projects, 2.hours.to_i) do
      assert_no_difference -> { Notifications::Projects::DevlogCapApproaching.count } do
        DevlogCapWarningJob.perform_now
      end
    end
  end

  test "does not notify twice within the same devlog window" do
    HackatimeService.stub(:fetch_total_seconds_for_projects, 9.hours.to_i) do
      assert_difference -> { Notifications::Projects::DevlogCapApproaching.count }, 1 do
        DevlogCapWarningJob.perform_now
        DevlogCapWarningJob.perform_now
      end
    end
  end

  test "posting a devlog re-arms the warning" do
    create_devlog(@project, at: 9.hours.ago)
    Notifications::Projects::DevlogCapApproaching.create!(
      recipient: @owner, record: @project,
      params: { "unposted_seconds" => 9.hours.to_i }, created_at: 10.hours.ago
    )

    HackatimeService.stub(:fetch_total_seconds_for_projects, 9.hours.to_i) do
      assert_difference -> { Notifications::Projects::DevlogCapApproaching.count }, 1 do
        DevlogCapWarningJob.perform_now
      end
    end
  end

  test "skips the Hackatime call entirely for recently-devlogged projects" do
    create_devlog(@project, at: 1.hour.ago)
    api_calls = 0
    counter = ->(*_args, **_kwargs) { api_calls += 1; 9.hours.to_i }

    HackatimeService.stub(:fetch_total_seconds_for_projects, counter) do
      assert_no_difference -> { Notifications::Projects::DevlogCapApproaching.count } do
        DevlogCapWarningJob.perform_now
      end
    end

    assert_equal 0, api_calls
  end

  test "skips owners without a hackatime identity" do
    @owner.identities.where(provider: "hackatime").destroy_all

    HackatimeService.stub(:fetch_total_seconds_for_projects, 9.hours.to_i) do
      assert_no_difference -> { Notifications::Projects::DevlogCapApproaching.count } do
        DevlogCapWarningJob.perform_now
      end
    end
  end

  private

  def create_devlog(project, at:)
    devlog = Post::Devlog.new(body: "work log", duration_seconds: 1.hour, created_at: at)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: @owner, postable: devlog, created_at: at)
    devlog
  end
end
