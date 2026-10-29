require "test_helper"

class ServerTimeControllerTest < ActionDispatch::IntegrationTest
  test "public clock uses server time and confirms the deadline without caching" do
    deadline = Rails.application.config.stardance_ends_at
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
