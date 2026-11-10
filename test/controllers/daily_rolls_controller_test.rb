require "test_helper"

class DailyRollsControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  setup do
    @user = create_user(slack_id: "U_RNG_ROLLER", display_name: "rng_roller")
    sign_in @user
  end

  test "rolling works on the last day" do
    travel_to(DailyRoll::LAST_ROLL_ON.in_time_zone.end_of_day - 1.minute) do
      assert_difference -> { DailyRoll.count }, 1 do
        post daily_roll_path
      end
    end
  end

  test "rolling is closed after the last day" do
    travel_to((DailyRoll::LAST_ROLL_ON + 1).in_time_zone.beginning_of_day) do
      assert_no_difference -> { DailyRoll.count } do
        post daily_roll_path
      end

      assert_response :forbidden
    end
  end
end
