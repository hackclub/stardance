require "test_helper"

class HackatimeServiceTest < ActiveSupport::TestCase
  # Regression guard for the duplicate-definition bug: a second `fetch_api_key`
  # under `private` once shadowed the public one, so the heartbeat forwarder's
  # `HackatimeService.fetch_api_key(token)` raised
  # `NoMethodError (private method 'fetch_api_key')` and no Lookout time ever
  # reached Hackatime. respond_to? is false for private methods, so this fails
  # the moment the public definition is shadowed again.
  test "fetch_api_key is public and callable with an explicit receiver" do
    assert_respond_to HackatimeService, :fetch_api_key,
      "HackatimeService.fetch_api_key must stay public — LookoutHeartbeatForwarder calls it with an explicit receiver"
  end

  test "fetch_api_key short-circuits to nil for a blank token without hitting the network" do
    assert_nil HackatimeService.fetch_api_key("")
    assert_nil HackatimeService.fetch_api_key(nil)
  end
end
