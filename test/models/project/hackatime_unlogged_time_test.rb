require "test_helper"

class Project::HackatimeUnloggedTimeTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @owner = create_user(slack_id: "U059VC0UDEU", display_name: "mahad")
    @project = Project.create!(title: "Late heartbeats", description: "Testing cumulative Hackatime totals")
    @project.memberships.create!(user: @owner, role: :owner)
    User::HackatimeProject.insert_all!([
      { user_id: @owner.id, project_id: @project.id, name: "late-heartbeats", created_at: Time.current, updated_at: Time.current }
    ])
  end

  test "fetches time from the event start" do
    at = Time.zone.parse("2026-06-10 12:00:00")
    request = nil
    fetch = lambda do |uid, keys, **options|
      request = { uid: uid, keys: keys, options: options }
      2.hours.to_i
    end

    seconds = HackatimeService.stub(:fetch_total_seconds_for_projects, fetch) do
      @project.unlogged_hackatime_seconds("ht-owner", user: @owner, at: at, access_token: "secret")
    end

    assert_equal 2.hours.to_i, seconds
    assert_equal "ht-owner", request[:uid]
    assert_equal [ "late-heartbeats" ], request[:keys]
    assert_equal HackatimeService::START_DATE, request[:options][:start_date]
    assert_equal at.iso8601, request[:options][:end_date]
  end

  test "includes late heartbeats in the next devlog without double counting logged time" do
    create_devlog(user: @owner, duration: 1.hour, at: 1.day.ago)

    seconds = HackatimeService.stub(:fetch_total_seconds_for_projects, 2.5.hours.to_i) do
      @project.unlogged_hackatime_seconds("ht-owner", user: @owner)
    end

    assert_equal 1.5.hours.to_i, seconds
  end

  test "does not subtract granted test time" do
    create_devlog(user: @owner, duration: 15.minutes, at: 1.day.ago, key_snapshot: "test")

    seconds = HackatimeService.stub(:fetch_total_seconds_for_projects, 1.hour.to_i) do
      @project.unlogged_hackatime_seconds("ht-owner", user: @owner)
    end

    assert_equal 1.hour.to_i, seconds
  end

  test "subtracts legacy devlogs without a project key snapshot" do
    create_devlog(user: @owner, duration: 1.hour, at: 1.day.ago, key_snapshot: nil)

    seconds = HackatimeService.stub(:fetch_total_seconds_for_projects, 2.hours.to_i) do
      @project.unlogged_hackatime_seconds("ht-owner", user: @owner)
    end

    assert_equal 1.hour.to_i, seconds
  end

  private

  def create_devlog(user:, duration:, at:, key_snapshot: "late-heartbeats")
    devlog = Post::Devlog.new(
      body: "Progress update",
      duration_seconds: duration,
      hackatime_projects_key_snapshot: key_snapshot,
      created_at: at
    )
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: @project, user: user, postable: devlog, created_at: at)
  end
end
