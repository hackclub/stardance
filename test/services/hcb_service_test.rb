require "test_helper"

class HCBServiceTest < ActiveSupport::TestCase
  setup do
    HCBCredential.delete_all
    @credential = HCBCredential.create!(
      client_id: "cid",
      client_secret: "secret",
      access_token: "old-access",
      refresh_token: "the-refresh-token",
      redirect_uri: "https://stardance.hackclub.com/auth/hcb/callback",
      base_url: "https://hcb.test",
      slug: "stardance"
    )
  end

  teardown { HCBCredential.delete_all }

  # RFC 6749 §5.1 makes refresh_token optional in a refresh response. Writing it
  # back unconditionally erased the only token that could get a new one, which
  # left every later refresh posting a blank token for `invalid_request`.
  test "a refresh response without a refresh_token keeps the stored one" do
    stub_token_response("access_token" => "new-access") do
      assert HCBService.refresh_token!
    end

    @credential.reload
    assert_equal "new-access", @credential.access_token
    assert_equal "the-refresh-token", @credential.refresh_token
  end

  test "a refresh response with a rotated refresh_token stores the new one" do
    stub_token_response("access_token" => "new-access", "refresh_token" => "rotated") do
      assert HCBService.refresh_token!
    end

    @credential.reload
    assert_equal "new-access", @credential.access_token
    assert_equal "rotated", @credential.refresh_token
  end

  test "a blank stored refresh token fails with an actionable message" do
    @credential.update!(refresh_token: nil)

    # HCBError is defined inside hcb_service.rb, which Zeitwerk maps to
    # HCBService, so the constant only exists once that file has been loaded.
    # Referencing the service first keeps this independent of test order.
    error_class = HCBService && HCBError

    error = assert_raises(error_class) { HCBService.refresh_token! }

    assert_match(/re-authorize HCB/, error.message)
  end

  # The org used to come from an ivar that `conn` assigned on the NEXT line, so
  # the first grant in a fresh process posted to `organizations//card_grants`.
  test "a grant with no explicit organization uses the credential's slug" do
    path = capture_grant_path { HCBService.create_card_grant(email: "a@b.test", amount_cents: 100) }

    assert_equal "/api/v4/organizations/stardance/card_grants", path
  end

  test "a grant can still target another organization explicitly" do
    path = capture_grant_path do
      HCBService.create_card_grant(email: "a@b.test", amount_cents: 100, organization: "stardance-hardware")
    end

    assert_equal "/api/v4/organizations/stardance-hardware/card_grants", path
  end

  private

  # Records the path a card-grant POST actually goes to.
  def capture_grant_path
    requested = nil
    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.post(%r{/card_grants\z}) do |env|
      requested = env.url.path
      [ 200, { "Content-Type" => "application/json" }, { "id" => "grant_1" }.to_json ]
    end
    connection = Faraday.new(url: "https://hcb.test/api/v4/") do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.adapter :test, stubs
    end

    Faraday.stub(:new, ->(*, **, &_blk) { connection }) { yield }
    requested
  end

  # Swaps in a Faraday test adapter for the token endpoint only.
  def stub_token_response(body)
    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.post("/api/v4/oauth/token") { [ 200, { "Content-Type" => "application/json" }, body.to_json ] }
    connection = Faraday.new(url: "https://hcb.test/api/v4/") do |f|
      f.request :url_encoded
      f.response :json, content_type: /\bjson$/
      f.adapter :test, stubs
    end

    # A callable so the service's configuration block is skipped rather than
    # being invoked with no builder.
    Faraday.stub(:new, ->(*, **, &_blk) { connection }) { yield }
  end
end
