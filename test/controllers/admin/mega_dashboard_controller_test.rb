require "test_helper"

class Admin::MegaDashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(slack_id: "U_MEGA_ADMIN", display_name: "mega_admin", email: "mega_admin@example.test")
    @admin.grant_role!(:admin)
  end

  test "admin sees the shell with a frame per queue" do
    sign_in @admin

    get admin_mega_dashboard_path

    assert_response :success
    assert_match(/[A-Z][a-z]+ [A-Z][a-z]+ [A-Z][a-z]+ Dashboard/, response.body)
    assert_match "mega-dash-overview", response.body
    assert_match "mega-dash-waterfall", response.body
    assert_select "turbo-frame#mega-dash-mihis", count: 0
    assert_no_match "Daily active mihis", response.body
    Admin::MegaDashboard::Queue.keys.each do |key|
      assert_match "mega-dash-queue-#{key}", response.body
    end
  end

  test "the title is three superlatives and reshuffles" do
    sign_in @admin

    titles = 8.times.map do
      get admin_mega_dashboard_path
      response.body[%r{<h1>([^<]+)</h1>}, 1]
    end

    titles.each { |title| assert_match(/\A(\w+ ){3}Dashboard\z/, title) }
    assert titles.uniq.size > 1, "expected the title to vary across requests"
  end

  test "non-admin is denied" do
    sign_in users(:two)

    get admin_mega_dashboard_path

    assert_response :not_found
  end

  test "period falls back to the default when unrecognised" do
    sign_in @admin

    get admin_mega_dashboard_path(period: "nonsense")

    assert_response :success
    assert_match "sections/overview?period=#{Admin::MegaDashboard::QueueStats::DEFAULT_PERIOD}", response.body
  end

  test "overview section renders a row for every queue" do
    sign_in @admin

    get admin_mega_dashboard_section_path(section: "overview")

    assert_response :success
    Admin::MegaDashboard::Queue.all.each { |queue| assert_match queue.label, response.body }
  end

  test "every queue section renders" do
    sign_in @admin

    Admin::MegaDashboard::Queue.keys.each do |key|
      get admin_mega_dashboard_section_path(section: "queue:#{key}")

      assert_response :success, "queue section #{key} did not render"
      assert_match "mega-dash-queue-#{key}", response.body
    end
  end

  test "waterfall section renders each payout path" do
    sign_in @admin

    get admin_mega_dashboard_section_path(section: "waterfall")

    assert_response :success
    Admin::MegaDashboard::Waterfall::PATHS.each_value { |label| assert_match label, response.body }
  end

  test "every standalone section renders" do
    sign_in @admin

    %w[money nps votes jelly fulfillment].each do |section|
      get admin_mega_dashboard_section_path(section: section)

      assert_response :success, "#{section} section did not render"
      assert_match "mega-dash-#{section}", response.body
    end
  end

  test "the shell frames every section" do
    sign_in @admin

    get admin_mega_dashboard_path

    %w[overview waterfall money nps votes jelly fulfillment].each do |section|
      assert_match "mega-dash-#{section}", response.body
    end
  end

  test "unknown section is rejected" do
    sign_in @admin

    get admin_mega_dashboard_section_path(section: "nope")

    assert_response :bad_request
  end

  test "removed mihis section is unavailable" do
    sign_in @admin

    get admin_mega_dashboard_section_path(section: "mihis")

    assert_response :bad_request
  end

  test "unknown queue key is not found" do
    sign_in @admin

    get admin_mega_dashboard_section_path(section: "queue:not_a_queue")

    assert_response :not_found
  end
end
