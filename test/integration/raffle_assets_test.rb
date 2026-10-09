require "test_helper"

class RaffleAssetsTest < ActionDispatch::IntegrationTest
  # Production sets asset_host to the main stardance host. Fonts and module
  # scripts loaded cross-origin from it are blocked on the raffle subdomain,
  # so raffle pages must reference /assets on their own host.
  test "raffle pages load assets same-origin while the main app keeps its asset host" do
    with_asset_host("https://stardance.example.com") do
      host! "raffle.example.com"
      get "/"
      assert_response :success
      assert_select "link[rel=stylesheet][href^='/assets/']"
      assert_select "script[src^='/assets/']"
      assert_select "link[href^='https://stardance.example.com'], script[src^='https://stardance.example.com']", count: 0

      host! "www.example.com"
      get "/"
      assert_response :success
      assert_select "link[rel=stylesheet][href^='https://stardance.example.com/assets/']"
    end
  end

  private

  def with_asset_host(host)
    original = ActionController::Base.asset_host
    ActionController::Base.asset_host = host
    yield
  ensure
    ActionController::Base.asset_host = original
  end
end
