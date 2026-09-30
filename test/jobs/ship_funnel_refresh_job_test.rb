require "test_helper"

class ShipFunnelRefreshJobTest < ActiveSupport::TestCase
  FUNNEL = { links: [], generated_at: Time.current }.freeze

  # The test environment's null store drops every write, and these are about the cache
  setup do
    @cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @cache }

  test "a queued refresh leaves an already warm cache alone" do
    Rails.cache.write(ShipFunnel::CACHE_KEY, FUNNEL)

    ShipFunnel.stub(:compute, -> { flunk "should not recompute a warm cache" }) { ShipFunnelRefreshJob.perform_now }

    assert_equal FUNNEL, ShipFunnel.cached
  end

  test "the scheduled refresh recomputes even when the cache is warm" do
    Rails.cache.write(ShipFunnel::CACHE_KEY, { stale: true })

    ShipFunnel.stub(:compute, FUNNEL) { ShipFunnelRefreshJob.perform_now(force: true) }

    assert_equal FUNNEL, ShipFunnel.cached
  end
end
