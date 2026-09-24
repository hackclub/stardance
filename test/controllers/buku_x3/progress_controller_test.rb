require "test_helper"

class BukuX3::ProgressControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @event = BukuX3::Event.create!(key: BukuX3::Event::KEY, unlocked_at: 1.minute.ago, destruction_minutes: 4500)
    Flipper.disable(:bukux3)
  end

  teardown do
    Flipper.disable(:bukux3)
    Flipper.disable(:blackhole)
  end

  test "non-local development pages have no event test buttons or simulator panels" do
    sign_in(@user)
    Flipper.enable(:blackhole)
    Rails.env.stub(:development?, true) do
      get home_path
      assert_response :success
      assert_select ".blackhole, .buku-x3-preview, .event-simulator, .blackhole__panel", count: 0

      Flipper.enable(:bukux3)
      get home_path
      assert_response :success
      assert_select ".blackhole", count: 1
      assert_select ".buku-x3-preview, .event-simulator, .blackhole__panel", count: 0
    end
  end

  test "live page renders one server-driven effect without simulator controls" do
    sign_in(@user)
    Flipper.enable_actor(:bukux3, @user)
    get home_path
    assert_response :success
    assert_select ".blackhole[data-blackhole-intensity-value='1.5']", count: 1
    assert_select ".blackhole__panel", count: 0
    assert_select ".buku-x3-simulator", count: 0
    assert_select ".blackhole[data-blackhole-progress-url-value='#{buku_x3_progress_path(format: :json)}']"
  end

  test "only exposes shared intensity and team totals, not individual contributions" do
    sign_in(@user)
    Flipper.enable_actor(:bukux3, @user)
    get buku_x3_progress_path(format: :json)
    assert_response :success
    assert_equal({ "percent" => 1.5, "visual_intensity" => 100, "hours" => { "buku" => 0, "bean" => 0 } }, response.parsed_body)
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "site damage waits for both intro and role reveal completion" do
    sign_in(@user)
    Flipper.enable_actor(:bukux3, @user)
    @user.update!(onboarded_at: Time.current, things_dismissed: [])
    get home_path
    assert_select ".blackhole[data-blackhole-awaiting-reveal-value='true']"
    @user.dismiss_thing!("bukux3_intro")
    get home_path
    assert_select ".blackhole[data-blackhole-awaiting-reveal-value='true']"
    @user.dismiss_thing!("bukux3_role_reveal")
    get home_path
    assert_select ".blackhole[data-blackhole-awaiting-reveal-value='false']"
  end

  test "starts a quarter damaged before accounting captures a cutoff" do
    sign_in(@user)
    Flipper.enable(:bukux3)
    @event.update!(unlocked_at: nil)
    get buku_x3_progress_path(format: :json)
    assert_equal({ "percent" => 25, "visual_intensity" => 100, "hours" => { "buku" => 0, "bean" => 0 } }, response.parsed_body)
  end

  test "signed out visitors cannot access progress" do
    Flipper.enable(:bukux3)
    get buku_x3_progress_path(format: :json)
    assert_response :unauthorized
  end

  test "visual intensity is sent independently of damage and hours on first load and polls" do
    sign_in(@user)
    Flipper.enable(:bukux3)
    @event.update!(visual_intensity: 0)
    get home_path
    assert_select ".blackhole[data-blackhole-intensity-value='1.5'][data-blackhole-visual-intensity-value='0']"
    get buku_x3_progress_path(format: :json)
    assert_equal 0, response.parsed_body["visual_intensity"]
    assert_equal 1.5, response.parsed_body["percent"]
  end

  test "disabled flag denies access" do
    sign_in(@user)
    get buku_x3_progress_path(format: :json)
    assert_response :forbidden
  end
end
