require "test_helper"

class BukuX3::RevealsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(onboarded_at: Time.current, things_dismissed: [])
    @event = BukuX3::Event.create!(key: BukuX3::Event::KEY, unlocked_at: 1.minute.ago)
    Flipper.enable(:bukux3)
    sign_in(@user)
  end

  teardown { Flipper.disable(:bukux3) }

  test "simulator is available only on local development hosts" do
    host! "localhost"
    get home_path
    assert_select ".event-simulator", count: 0
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      get home_path
      assert_select ".event-simulator", count: 1
      assert_select "[data-blackhole-simulator-enabled-value='true']", count: 1
      host! "stardance.example"
      get home_path
      assert_select ".event-simulator", count: 0
    end
  end

  test "local simulator is usable without enabling the event flag" do
    Flipper.disable(:bukux3)
    host! "localhost"
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      get home_path
      assert_select ".event-simulator", count: 1
      assert_select "[data-blackhole-intensity-value='0'][data-blackhole-progress-url-value='']", count: 1
    end
  end

  test "local simulator respects the particle preference saved through settings" do
    host! "localhost"
    sign_in(@user)
    patch my_settings_path, params: { particle_effects_enabled: "0" }
    assert_redirected_to root_path
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      get home_path
      assert_response :success
      assert_select "[data-blackhole-particles-enabled-value='false']", count: 1
      assert_select ".event-simulator input[name='particles'][disabled]:not([checked])", count: 1
    end
  end

  test "dashboard renders the saved particle preference without disabling damage" do
    @user.update!(things_dismissed: %w[bukux3_intro bukux3_role_reveal])
    [ false, true ].each do |enabled|
      @user.preference.update!(particle_effects_enabled: enabled)
      get home_path
      assert_response :success
      assert_select ".blackhole[data-blackhole-particles-enabled-value='#{enabled}'][data-blackhole-awaiting-reveal-value='false']", count: 1
      assert_select "input#particle_effects_enabled[type='checkbox']", count: 1
      assert_select "input#particle_effects_enabled[checked]", count: enabled ? 1 : 0
    end
  end

  test "first load contains only the explanation, never a prefetched role" do
    BukuX3::Assignment.stub(:buku?, ->(_) { flunk "role must wait until after intro" }) do
      get home_path
    end
    assert_response :success
    assert_select ".visual-novel[data-visual-novel-dismiss-thing-value='bukux3_intro']", count: 1
    assert_select "dialog.buku-x3-reveal", count: 0
    assert_select ".buku-x3-status", count: 0
  end

  test "reveal endpoint requires the intro to be completed" do
    BukuX3::Assignment.stub(:buku?, ->(_) { flunk "premature role assignment" }) do
      get buku_x3_reveal_path
    end
    assert_response :forbidden
  end

  test "finishing the intro permits the bean reveal, whose dismissal persists" do
    post my_dismissals_path, params: { thing_name: "bukux3_intro" }, as: :json
    assert_response :success
    BukuX3::Assignment.stub(:buku?, false) { get buku_x3_reveal_path }
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "dialog.buku-x3-reveal--bean", count: 1
    assert_select ".buku-x3-reveal__title em", text: "bean"
    post my_dismissals_path, params: { thing_name: "bukux3_role_reveal" }, as: :json
    get buku_x3_reveal_path
    assert_select "dialog.buku-x3-reveal", count: 0
    BukuX3::Assignment.stub(:buku?, false) { get home_path }
    assert_select ".buku-x3-status__role", text: "you're a bean"
    assert_select ".rocket-progress", count: 0
  end

  test "completed intro and flag suffice without a milestone" do
    @user.dismiss_thing!("bukux3_intro")
    @event.update!(unlocked_at: nil)
    get buku_x3_reveal_path
    assert_response :success
    assert_select "dialog.buku-x3-reveal", count: 1
  end

  test "flag off denies reveal even after the intro" do
    @user.dismiss_thing!("bukux3_intro")
    Flipper.disable(:bukux3)
    get buku_x3_reveal_path
    assert_response :forbidden
  end

  test "preview cannot bypass the event outside development" do
    get buku_x3_reveal_path(preview: "bean")
    assert_response :forbidden
  end

  test "home preview parameter cannot reveal a role outside development" do
    BukuX3::Assignment.stub(:buku?, ->(_) { flunk "preview bypassed the intro" }) do
      get home_path(buku_preview: "bean")
    end
    assert_response :success
    assert_select ".buku-x3-status", count: 0
    assert_select "turbo-frame#buku_x3_home_status", count: 1
  end
end
