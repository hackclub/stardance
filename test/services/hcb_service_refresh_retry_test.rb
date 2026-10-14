require "test_helper"

# Forces app/services/hcb_service.rb to autoload now, since Zeitwerk only
# indexes the file under its matching constant (HCBService) — the bare
# HCBError class defined alongside it in the same file wouldn't otherwise be
# defined yet if a test referencing it runs before anything touches HCBService.
HCBService

class HCBServiceRefreshRetryTest < ActiveSupport::TestCase
  setup do
    HCBCredential.delete_all
    @creds = HCBCredential.create!(
      client_id: "demo-client",
      client_secret: "demo-secret",
      refresh_token: "old-refresh-token",
      access_token: "old-access-token",
      base_url: "https://hcb.test",
      redirect_uri: "https://example.com/callback"
    )
  end

  teardown { HCBCredential.delete_all }

  # Temporarily replaces an instance method on `klass`, then restores the
  # original. Used to force failures out of `update!` without needing a real DB
  # outage, and to simulate losing the race for the credential row lock.
  def replace_method(klass, method_name, replacement)
    original = klass.instance_method(method_name)
    klass.send(:define_method, method_name) do |*args, **kwargs, &blk|
      replacement.call(self, *args, **kwargs, &blk)
    end
    yield
  ensure
    klass.send(:define_method, method_name, original)
  end

  # Stubs the token endpoint and returns how many refreshes actually went out,
  # so a test can assert a refresh was skipped rather than only that one
  # succeeded.
  def stub_token_endpoint(body, &block)
    calls = 0
    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.post("/api/v4/oauth/token") do
      calls += 1
      [ 200, { "Content-Type" => "application/json" }, body.to_json ]
    end
    connection = Faraday.new(url: "https://hcb.test/api/v4/") do |f|
      f.request :url_encoded
      f.response :json, content_type: /\bjson$/
      f.adapter :test, stubs
    end

    # A callable so the service's configuration block is skipped rather than
    # being invoked with no builder.
    Faraday.stub(:new, ->(*, **, &_blk) { connection }, &block)
    calls
  end

  test "a failed save raises an alert and leaves the old tokens in place" do
    attempts = 0
    always_fail = lambda do |_instance, *_args, **_kwargs|
      attempts += 1
      raise ActiveRecord::StatementInvalid, "simulated DB outage"
    end

    alerts = 0
    OperationalAlert.stub(:report, ->(*, **) { alerts += 1 }) do
      replace_method(HCBCredential, :update!, always_fail) do
        stub_token_endpoint("access_token" => "new-access-token") do
          error = assert_raises(HCBError) { HCBService.refresh_token! }
          assert_match(/failed to save/, error.message)
        end
      end
    end

    assert_equal 1, attempts, "the save runs inside with_lock's transaction, so a failure can't be retried in place"
    assert_equal 1, alerts, "losing rotated tokens bricks the credential and must page someone"
    assert_equal "old-access-token", @creds.reload.access_token, "credentials must not be left half-updated"
  end

  # HCB revokes the previous access token on every successful refresh, so a
  # second refresh queued behind the first would revoke the token the first one
  # just stored. Both processes would then 401 and take turns invalidating each
  # other, which is what made refresh look broken under any concurrency.
  test "refresh_token! skips the HCB call when another process already rotated the token" do
    # Stands in for the process that won the race, committing a new access token
    # while this one was waiting on the row lock.
    real_with_lock = HCBCredential.instance_method(:with_lock)
    winner_refreshed = lambda do |instance, &blk|
      instance.class.find(instance.id).update!(access_token: "winner-access-token")
      real_with_lock.bind(instance).call(&blk)
    end

    calls = nil
    replace_method(HCBCredential, :with_lock, winner_refreshed) do
      calls = stub_token_endpoint("access_token" => "should-never-be-used") do
        assert HCBService.refresh_token!, "the caller should be told to go ahead and retry"
      end
    end

    assert_equal 0, calls, "the winner's refresh already produced a usable token"
    assert_equal "winner-access-token", @creds.reload.access_token, "the winner's token must survive"
  end

  test "refresh_token! records the expiry HCB reports so the next refresh can happen ahead of a 401" do
    freeze_time do
      stub_token_endpoint("access_token" => "new-access-token", "expires_in" => 7200) do
        assert HCBService.refresh_token!
      end

      assert_equal 7200.seconds.from_now, @creds.reload.expires_at
    end
  end

  # A stale expires_at would put every single call through a proactive refresh.
  test "refresh_token! clears the expiry when HCB omits expires_in" do
    @creds.update!(expires_at: 1.hour.ago)

    stub_token_endpoint("access_token" => "new-access-token") do
      assert HCBService.refresh_token!
    end

    assert_nil @creds.reload.expires_at
  end

  test "refresh_token! reports an invalid_grant as needing re-authorization" do
    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.post("/api/v4/oauth/token") do
      [ 401, { "Content-Type" => "application/json" }, { "error" => "invalid_grant" }.to_json ]
    end
    connection = Faraday.new(url: "https://hcb.test/api/v4/") do |f|
      f.request :url_encoded
      f.response :json, content_type: /\bjson$/
      f.adapter :test, stubs
    end

    Faraday.stub(:new, ->(*, **, &_blk) { connection }) do
      error = assert_raises(HCBError) { HCBService.refresh_token! }
      assert_match(/re-authorize HCB/, error.message)
    end
  end

  test "refresh_due? is true only inside the margin, and never without a recorded expiry" do
    @creds.update!(expires_at: nil)
    assert_not HCBService.refresh_due?, "an unknown expiry must leave the 401 path as the only trigger"

    @creds.update!(expires_at: 1.hour.from_now)
    assert_not HCBService.refresh_due?

    @creds.update!(expires_at: (HCBService::EXPIRY_MARGIN - 1.minute).from_now)
    assert HCBService.refresh_due?, "a token about to expire mid-request should be refreshed first"

    @creds.update!(expires_at: 1.minute.ago)
    assert HCBService.refresh_due?
  end
end
