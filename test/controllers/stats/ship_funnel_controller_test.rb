require "test_helper"

class Stats::ShipFunnelControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  self.fixture_table_names = []

  FUNNEL = { links: [], unshipped_links: [], loops: { returned_twice: 1, goi_sent_back: 2, goi_twice: 3 },
             airtable_split: true, generated_at: Time.current }.freeze

  # The test environment's null store drops every write, and these are about the cache
  setup do
    @cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @cache }

  test "a cold cache asks visitors to check back and queues a refresh instead of computing" do
    assert_enqueued_with(job: ShipFunnelRefreshJob) { get stats_ship_funnel_path }

    assert_response :success
    assert_select ".ship-funnel__footer", /Check back in a minute/
    assert_select "[data-controller='ship-funnel']", count: 0
  end

  test "anyone can see the cached funnel, without the admin controls" do
    Rails.cache.write(ShipFunnel::CACHE_KEY, FUNNEL)

    assert_no_enqueued_jobs(only: ShipFunnelRefreshJob) { get stats_ship_funnel_path }

    assert_response :success
    assert_select "h1", "Jeremy Funnel"
    assert_select "[data-controller='ship-funnel'] svg[data-ship-funnel-target='chart']"
    assert_select ".ship-funnel__footer", /Loops not pictured/
    assert_select ".ship-funnel__refresh", count: 0
    assert_select ".ship-funnel__back", count: 0
  end

  test "an admin gets the update button and a way back to admin" do
    sign_in admin
    Rails.cache.write(ShipFunnel::CACHE_KEY, FUNNEL)

    get stats_ship_funnel_path

    assert_select ".ship-funnel__refresh"
    assert_select ".ship-funnel__back"
  end

  test "only an admin can recompute" do
    sign_in create_user(slack_id: "U_SHIP_FUNNEL_MEMBER", display_name: "ship_funnel_member")

    ShipFunnel.stub(:compute, -> { flunk "a non-admin must not trigger a recompute" }) { post refresh_stats_ship_funnel_path }

    assert_response :forbidden
    assert_nil ShipFunnel.cached
  end

  private

  def admin
    create_user(slack_id: "U_SHIP_FUNNEL_ADMIN", display_name: "ship_funnel_admin").tap { |user| user.grant_role!(:admin) }
  end
end
