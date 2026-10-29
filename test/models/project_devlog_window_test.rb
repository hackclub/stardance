require "test_helper"

# A Hackatime project linked after earlier devlogs used to share the window
# opened by the last devlog, so its time from before then was never counted
# (#775). Each key's window now opens at the last devlog that counted it.
class ProjectDevlogWindowTest < ActiveSupport::TestCase
  setup do
    @owner = create_user(slack_id: "U_PDW", display_name: "pdw")
    @project = Project.create!(title: "Window")
    @project.memberships.create!(user: @owner, role: :owner)
    User::HackatimeProject.create!(user: @owner, project: @project, name: "first")
    @first_devlog_at = 2.days.ago
    create_devlog(at: @first_devlog_at, snapshot: "first")
  end

  test "a key linked after the last devlog counts from the project's first window" do
    User::HackatimeProject.create!(user: @owner, project: @project, name: "second")
    calls = record_hackatime_calls { @project.seconds_coded_in_devlog_window("uid") }

    first_window = @project.devlog_window_start(@first_devlog_at)
    assert_equal({ [ "first" ] => @first_devlog_at.iso8601, [ "second" ] => first_window.iso8601 }, calls)
  end

  test "keys that were already counted share the window from the last devlog" do
    calls = record_hackatime_calls { @project.seconds_coded_in_devlog_window("uid") }

    assert_equal({ [ "first" ] => @first_devlog_at.iso8601 }, calls)
  end

  test "sums the time across windows" do
    User::HackatimeProject.create!(user: @owner, project: @project, name: "second")

    HackatimeService.stub(:fetch_total_seconds_for_projects, 10.minutes.to_i) do
      assert_equal 20.minutes.to_i, @project.seconds_coded_in_devlog_window("uid")
    end
  end

  test "a key with a comma in its name still matches its snapshot" do
    project = Project.create!(title: "Commas")
    project.memberships.create!(user: @owner, role: :owner)
    User::HackatimeProject.create!(user: @owner, project: project, name: "a,b")
    devlog_at = 1.day.ago
    create_devlog(at: devlog_at, snapshot: "a,b", project: project)

    assert_equal devlog_at.to_i, project.devlog_window_start(Time.current, key: "a,b").to_i
  end

  test "a devlog with a typed names snapshot only closes its own keys' windows" do
    second_devlog_at = 1.day.ago
    create_devlog(at: second_devlog_at, snapshot: nil, names: [ "first" ])
    User::HackatimeProject.create!(user: @owner, project: @project, name: "second")

    assert_equal second_devlog_at.to_i, @project.devlog_window_start(Time.current, key: "first").to_i
    assert_equal @project.devlog_window_start(@first_devlog_at).to_i, @project.devlog_window_start(Time.current, key: "second").to_i
  end

  test "a test-time devlog still closes every key's window" do
    test_devlog_at = 1.day.ago
    create_devlog(at: test_devlog_at, snapshot: "test")
    User::HackatimeProject.create!(user: @owner, project: @project, name: "second")

    assert_equal test_devlog_at.to_i, @project.devlog_window_start(Time.current, key: "second").to_i
  end

  test "a cutoff ends the window early" do
    cutoff = 1.day.ago
    end_dates = []
    stub = ->(_uid, _keys, start_date:, end_date:, access_token:) { end_dates << end_date; 0 }
    HackatimeService.stub(:fetch_total_seconds_for_projects, stub) do
      @project.seconds_coded_in_devlog_window("uid", cutoff: cutoff)
    end

    assert_equal [ cutoff.iso8601 ], end_dates
  end

  test "a cutoff before the window opened counts nothing without calling hackatime" do
    HackatimeService.stub(:fetch_total_seconds_for_projects, ->(*) { flunk "should not call hackatime" }) do
      assert_equal 0, @project.seconds_coded_in_devlog_window("uid", cutoff: 3.days.ago)
    end
  end

  private

  def record_hackatime_calls
    calls = {}
    stub = ->(_uid, keys, start_date:, end_date:, access_token:) { calls[keys.sort] = start_date; 0 }
    HackatimeService.stub(:fetch_total_seconds_for_projects, stub) { yield }
    calls
  end

  def create_devlog(at:, snapshot:, project: @project, names: nil)
    devlog = Post::Devlog.new(body: "work log", duration_seconds: 1.hour, created_at: at,
      hackatime_projects_key_snapshot: snapshot, hackatime_project_names_snapshot: names)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: @owner, postable: devlog, created_at: at)
    devlog
  end
end
