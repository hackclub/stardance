require "test_helper"

class ServerTimeControllerTest < ActionDispatch::IntegrationTest
  setup { Flipper.disable(:finaleondemand) }
  teardown { Flipper.disable(:finaleondemand) }

  test "on demand defaults off and can be enabled globally for signed out viewers" do
    get server_time_path, as: :json
    assert_equal false, response.parsed_body.dig("finale", "on_demand")
    Flipper.enable(:finaleondemand)
    get server_time_path, as: :json
    assert_equal true, response.parsed_body.dig("finale", "on_demand")
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "actor-scoped production preview is available only to the selected viewer" do
    Flipper.enable_actor(:finaleondemand, users(:one))
    get server_time_path, as: :json
    assert_equal false, response.parsed_body.dig("finale", "on_demand")
    sign_in(users(:one))
    get server_time_path, as: :json
    assert_equal true, response.parsed_body.dig("finale", "on_demand")
    sign_in(users(:two))
    get server_time_path, as: :json
    assert_equal false, response.parsed_body.dig("finale", "on_demand")
    Flipper.disable(:finaleondemand)
    sign_in(users(:one))
    get server_time_path, as: :json
    assert_equal false, response.parsed_body.dig("finale", "on_demand")
  end

  test "public timeline publishes the configured file and exact duration without fetching media" do
    Rails.application.config.stub(:stardance_finale_video_url, "/videos/finale.mp4") do
      Rails.application.config.stub(:stardance_finale_video_duration_seconds, 123.456) do
        get server_time_path, as: :json
        assert_response :success
        assert_equal({ "video_url" => "/videos/finale.mp4", "duration_seconds" => 123.456, "on_demand" => false }, response.parsed_body["finale"])
      end
    end
  end

  test "invalid video durations do not create an endless live window" do
    [ 0, -1, Float::INFINITY, Float::NAN ].each do |duration|
      Rails.application.config.stub(:stardance_finale_video_duration_seconds, duration) do
        get server_time_path, as: :json
        assert_response :success
        assert_equal 0, response.parsed_body.dig("finale", "duration_seconds")
      end
    end
  end

  test "countdown targets 12:15 PM Eastern November 1 without moving the October 31 event deadline" do
    assert_equal Time.utc(2026, 11, 1, 17, 15), Rails.application.config.stardance_finale_at
    assert_equal Time.find_zone!("America/New_York").local(2026, 10, 31).end_of_day,
                 Rails.application.config.stardance_ends_at

    travel_to Rails.application.config.stardance_ends_at + 1.second do
      get server_time_path, as: :json
      assert_response :success
      assert_equal false, response.parsed_body["ended"]
      assert_equal "2026-11-01T12:15:00.000-05:00", response.parsed_body["ends_at"]
    end
  end

  test "public clock uses server time and confirms the deadline without caching" do
    deadline = Rails.application.config.stardance_finale_at
    [ [ deadline - 1.second, false ], [ deadline, true ], [ deadline + 2.days, true ] ].each do |now, ended|
      travel_to now, with_usec: true do
        get server_time_path, as: :json
        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_equal Time.current.iso8601(3), response.parsed_body["now"]
        assert_equal deadline.iso8601(3), response.parsed_body["ends_at"]
        assert_equal ended, response.parsed_body["ended"]
      end
    end
  end
end
