require "test_helper"

class ServerTimeControllerTest < ActionDispatch::IntegrationTest
  test "countdown targets noon Eastern November 1 without moving the October 31 event deadline" do
    assert_equal Time.utc(2026, 11, 1, 17), Rails.application.config.stardance_finale_at
    assert_equal Time.find_zone!("America/New_York").local(2026, 10, 31).end_of_day,
                 Rails.application.config.stardance_ends_at

    travel_to Rails.application.config.stardance_ends_at + 1.second do
      get server_time_path, as: :json
      assert_response :success
      assert_equal false, response.parsed_body["ended"]
      assert_equal "2026-11-01T12:00:00.000-05:00", response.parsed_body["ends_at"]
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
