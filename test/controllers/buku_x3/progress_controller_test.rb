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
      assert_select ".blackhole[data-blackhole-intensity-value='0']", count: 1
      assert_select ".buku-x3-preview, .event-simulator, .blackhole__panel", count: 0

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
    assert_select ".blackhole[data-stardance-finale-ends-at-value='#{Rails.application.config.stardance_ends_at.iso8601(3)}']"
    assert_select "[data-action='stardance-finale#preview']", count: 0
  end

  test "finale deadline is present even when the viewer hides the countdown" do
    sign_in(@user)
    Flipper.enable_actor(:bukux3, @user)
    @user.preference.update!(countdown_enabled: false)
    get home_path
    assert_select ".buku-x3-status__clock", count: 0
    assert_select ".blackhole[data-stardance-finale-ends-at-value='#{Rails.application.config.stardance_ends_at.iso8601(3)}']"
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

  test "late arrivals get the finale independently of the team flag and visual preferences" do
    sign_in(@user)
    @user.preference.update!(countdown_enabled: false, disintegration_effects_enabled: false, particle_effects_enabled: false)
    travel_to Rails.application.config.stardance_ends_at + 2.days do
      get home_path
      assert_response :success
      assert_select "[data-stardance-finale-seen-value='false'][data-stardance-finale-viewer-id-value='#{@user.id}']"
      assert_select ".stardance-finale__placeholder", text: "", count: 1
      assert_select ".stardance-finale__panel button, .stardance-finale__panel p", count: 0
      assert_select ".buku-x3-status__clock", count: 0
      assert_select ".blackhole[data-blackhole-disintegration-enabled-value='false'][data-blackhole-particles-enabled-value='false']"
      assert_not @user.preference.reload.disintegration_effects_enabled?
      assert_not @user.preference.particle_effects_enabled?
    end
  end

  test "finale completion is idempotent and belongs only to the current user" do
    sign_in(@user)
    2.times do
      post my_dismissals_path, params: { thing_name: "stardance_finale" }, as: :json
      assert_response :success
    end
    assert_equal 1, @user.reload.things_dismissed.count("stardance_finale")
    assert_not users(:two).has_dismissed?("stardance_finale")
    get home_path
    assert_select "[data-stardance-finale-seen-value='true']"
  end

  test "configured finale video replaces the placeholder and keeps replay local" do
    sign_in(@user)
    original_url = Rails.application.config.stardance_finale_video_url
    Rails.application.config.stardance_finale_video_url = "https://example.test/finale.mp4"
    get home_path
    assert_select ".stardance-finale__video[src='https://example.test/finale.mp4'][controls][playsinline]"
    assert_select ".stardance-finale__placeholder", count: 0
    assert_select "[data-stardance-finale-preview-enabled-value='false']"
  ensure
    Rails.application.config.stardance_finale_video_url = original_url
  end

  test "admin pages are not interrupted by the finale" do
    @user.update!(granted_roles: [ "admin" ])
    sign_in(@user)
    get admin_root_path
    assert_select ".stardance-finale", count: 0
  end
end
