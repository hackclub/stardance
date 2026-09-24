require "test_helper"

class Admin::BukuX3EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:tongyu)
    @event = BukuX3::Event.create!(key: BukuX3::Event::KEY, unlocked_at: 1.day.ago,
                                 destruction_minutes: BukuX3::Event::STARTING_DESTRUCTION_MINUTES)
  end

  test "admins can change intensity with an attributed accessible audit trail" do
    sign_in @admin
    cutoff = @event.unlocked_at
    assert_difference "@event.versions.count", 1 do
      patch admin_buku_x3_event_path, params: { buku_x3_event: { visual_intensity: 50, destruction_minutes: 0 } }
    end
    assert_redirected_to admin_jim_takeover_path
    assert_equal 50, @event.reload.visual_intensity
    assert_equal 25, @event.percent
    assert_equal cutoff, @event.unlocked_at
    version = @event.versions.last
    assert_equal @admin.id.to_s, version.whodunnit
    assert_equal [ 100, 50 ], version.changeset["visual_intensity"]
    get admin_audit_logs_path(item_type: "BukuX3::Event", changed_field: "visual_intensity")
    assert_response :success
    assert_includes response.body, "visual_intensity"
  end

  test "admin pages never render disintegration or the local simulator" do
    host! "localhost"
    sign_in @admin
    Flipper.enable(:bukux3)
    @admin.update!(onboarded_at: Time.current, things_dismissed: %w[bukux3_intro bukux3_role_reveal])
    @event.update!(destruction_minutes: BukuX3::Event::MAX_DESTRUCTION_MINUTES)
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      # Missions deliberately uses the application layout instead of admin.
      [ admin_root_path, admin_jim_takeover_path, admin_missions_path, admin_audit_logs_path ].each do |path|
        get path
        assert_response :success
        assert_select "[data-controller~='blackhole'], .event-simulator", count: 0
      end
      get home_path
      assert_response :success
      assert_select "[data-controller~='blackhole']", count: 1
    end
  ensure
    Flipper.disable(:bukux3)
  end

  test "admins can download an uncached csv with an accessible attributed audit entry" do
    sign_in @admin
    assert_difference "PaperTrail::Version.where(event: 'export_bukux2_contributors').count", 1 do
      post admin_bukux2_contributors_export_path
    end
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_includes response.headers["Content-Disposition"], "attachment"
    assert_includes response.headers["Content-Disposition"], "bukux2-contributors-through-2026-09-24.csv"
    assert_equal RocketProgress::ContributorExport::HEADERS, CSV.parse(response.body).first
    version = PaperTrail::Version.where(event: "export_bukux2_contributors").last
    assert_equal @admin.id.to_s, version.whodunnit
    assert_equal [ nil, 0 ], version.changeset["exported_users"]
    get admin_audit_logs_path(event: "export_bukux2_contributors")
    assert_response :success
    assert_includes response.body, "export_bukux2_contributors"
  end

  test "export authorizes before reading participant data" do
    user = users(:one)
    user.grant_role!(:workshop_manager)
    sign_in user
    RocketProgress::ContributorExport.stub(:new, -> { flunk "must authorize first" }) do
      post admin_bukux2_contributors_export_path
    end
    assert_response :forbidden
    get admin_jim_takeover_path
    assert_select "form[action=?]", admin_bukux2_contributors_export_path, count: 0
  end

  test "signed out requests cannot export contributors" do
    assert_no_difference "PaperTrail::Version.where(event: 'export_bukux2_contributors').count" do
      post admin_bukux2_contributors_export_path
    end
    assert_response :not_found
  end

  test "off and double strength are allowed but malformed or out of range values are rejected" do
    sign_in @admin
    [ 0, 200, 100 ].each do |intensity|
      patch admin_buku_x3_event_path, params: { buku_x3_event: { visual_intensity: intensity } }
      assert_equal intensity, @event.reload.visual_intensity
    end
    [ -1, 201, "hello", "50.5" ].each do |intensity|
      assert_no_difference "@event.versions.count" do
        patch admin_buku_x3_event_path, params: { buku_x3_event: { visual_intensity: intensity } }
      end
      assert_equal 100, @event.reload.visual_intensity
      assert flash[:alert].present?
    end
  end

  test "staff without admin role cannot change intensity or see controls" do
    user = users(:one)
    user.grant_role!(:workshop_manager)
    sign_in user
    get admin_jim_takeover_path
    assert_response :success
    assert_select "canvas[data-buku-activity-chart-target='canvas']", count: 1
    assert_select ".admin-dashboard__event-controls", count: 0
    assert_no_difference "@event.versions.count" do
      patch admin_buku_x3_event_path, params: { buku_x3_event: { visual_intensity: 0 } }
    end
    assert_response :forbidden
    assert_equal 100, @event.reload.visual_intensity
  end

  test "setting intensity before launch does not unlock the event" do
    @event.destroy!
    sign_in @admin
    patch admin_buku_x3_event_path, params: { buku_x3_event: { visual_intensity: 75 } }
    event = BukuX3::Event.current
    assert_equal 75, event.visual_intensity
    assert_nil event.unlocked_at
    assert_not event.active?
    assert_equal 25, event.percent
  end

  test "signed out requests cannot change intensity" do
    assert_no_difference "@event.versions.count" do
      patch admin_buku_x3_event_path, params: { buku_x3_event: { visual_intensity: 0 } }, as: :json
    end
    assert_response :not_found # Admin routes are hidden from signed-out visitors.
    assert_equal 100, @event.reload.visual_intensity
  end

  test "jim takeover contains discoveries, chronological chart data and admin controls" do
    sign_in @admin
    BukuX3::Assignment.stub(:discovered_counts, { total: 1234, buku: 600, bean: 634 }) do
      get admin_jim_takeover_path
    end
    assert_response :success
    assert_select "h1", text: "the jim takeover"
    assert_select ".admin-dashboard__metric dd", text: "1,234"
    assert_select ".admin-dashboard__metric--buku dd", text: "600"
    assert_select ".admin-dashboard__metric--bean dd", text: "634"
    assert_select "[data-buku-activity-chart-data-value]" do |elements|
      data = JSON.parse(elements.first["data-buku-activity-chart-data-value"])
      assert_equal 14, data.length
      assert_equal data.map { |day| day["date"] }.sort, data.map { |day| day["date"] }
      assert data.all? { |day| day.key?("buku") && day.key?("bean") }
    end
    assert_select "table", count: 0
    assert_select "form[action=?]", admin_buku_x3_event_path
    assert_select "form[action=?][data-turbo='false']", admin_bukux2_contributors_export_path
  end

  test "ordinary users cannot access the event dashboard" do
    sign_in users(:one)
    BukuX3::Assignment.stub(:discovered_counts, -> { flunk "authorize before loading metrics" }) do
      get admin_jim_takeover_path
    end
    assert_response :not_found
  end
end
