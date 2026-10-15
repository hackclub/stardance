require "test_helper"

class Api::PrivacyControllerTest < ActionDispatch::IntegrationTest
  include PrivacyTokenHelper

  setup do
    @user = create_user(slack_id: "U_PRIVACY", display_name: "privacy-me")
  end

  test "rejects requests without a valid token" do
    with_privacy_jwks { post api_privacy_delete_path, headers: { "Authorization" => "Bearer nope" } }

    assert_response :unauthorized
    assert_equal({ "error" => "invalid_token" }, response.parsed_body)

    with_privacy_jwks { post api_privacy_delete_path }

    assert_response :unauthorized
    assert_equal({ "error" => "missing_token" }, response.parsed_body)
  end

  test "rejects a token for the other endpoint" do
    call(api_privacy_export_path, privacy_token(action: "delete"))

    assert_response :bad_request
    assert_equal({ "error" => "action_mismatch" }, response.parsed_body)
  end

  test "accepts each token once" do
    token = privacy_token(subject: { emails: [ "nobody@example.test" ] })
    call(api_privacy_delete_path, token)
    assert_response :success

    call(api_privacy_delete_path, token)

    assert_response :conflict
    assert_equal({ "error" => "replayed" }, response.parsed_body)
  end

  test "answers found false for someone it doesn't know" do
    call(api_privacy_delete_path, privacy_token(request_id: "req-404", subject: { emails: [ "nobody@example.test" ] }))

    assert_response :success
    assert_equal({ "request_id" => "req-404", "found" => false, "dry_run" => true, "deleted" => {}, "retained" => [] }, response.parsed_body)
  end

  test "only acts on the token, never on identifiers in the request" do
    call(api_privacy_delete_path, privacy_token(dry_run: false, subject: { emails: [ "nobody@example.test" ] }),
         params: { email: @user.email, slack_id: @user.slack_id })

    assert_response :success
    assert_equal false, response.parsed_body["found"]
    assert_equal "U_PRIVACY", @user.reload.slack_id
  end

  test "a dry run reports counts and leaves the account alone" do
    call(api_privacy_delete_path, privacy_token(request_id: "req-dry", subject: { slack_id: "U_PRIVACY" }))

    assert_response :success
    body = response.parsed_body
    assert_equal "req-dry", body["request_id"]
    assert body["found"]
    assert body["dry_run"]
    assert_equal 1, body["deleted"]["user_identities"]
    assert_includes body["retained"].pluck("type"), "account record"
    assert_equal "U_PRIVACY", @user.reload.slack_id
  end

  test "a real run erases the account" do
    call(api_privacy_delete_path, privacy_token(dry_run: false, subject: { identity_id: "hca-U_PRIVACY" }))

    assert_response :success
    assert_equal false, response.parsed_body["dry_run"]
    assert_nil @user.reload.slack_id
    assert_nil @user.email
  end

  test "export reports what is held and never changes anything, even for a real-run token" do
    call(api_privacy_export_path, privacy_token(action: "export", dry_run: false, subject: { slack_id: "U_PRIVACY" }))

    assert_response :success
    assert response.parsed_body["found"]
    assert_equal 1, response.parsed_body["deleted"]["user_identities"]
    assert_equal "U_PRIVACY", @user.reload.slack_id
    assert @user.identities.exists?
  end

  test "a dependency failure allows the same token to retry and success prevents replay" do
    jti = SecureRandom.uuid
    token = privacy_token(jti:, dry_run: false, subject: { slack_id: "U_PRIVACY" })
    client = Gorse::Client.new

    Gorse.stub(:enabled?, true) do
      Gorse::Client.stub(:new, client) do
        client.stub(:delete_user!, ->(*) { raise Faraday::ConnectionFailed, "unavailable" }) do
          call(api_privacy_delete_path, token)
        end

        assert_response :service_unavailable
        assert_equal({ "error" => "dependency_unavailable" }, response.parsed_body)
        assert_not PrivacyTokenUse.exists?(jti:)
        assert_equal "U_PRIVACY", @user.reload.slack_id
        assert @user.identities.exists?

        deleted_users = []
        client.stub(:delete_user!, ->(id) { deleted_users << id }) do
          call(api_privacy_delete_path, token)
        end

        assert_response :success
        assert_equal [ "user:#{@user.id}" ], deleted_users
        assert_nil @user.reload.slack_id
        assert_empty @user.identities
        assert PrivacyTokenUse.exists?(jti:)

        call(api_privacy_delete_path, token)
        assert_response :conflict
        assert_equal({ "error" => "replayed" }, response.parsed_body)
      end
    end
  end

  test "refuses staff accounts for a human to handle" do
    @user.grant_role!(:admin)

    call(api_privacy_delete_path, privacy_token(dry_run: false, subject: { slack_id: "U_PRIVACY" }))

    assert_response :conflict
    assert_equal({ "error" => "manual_review_required" }, response.parsed_body)
    assert_equal "U_PRIVACY", @user.reload.slack_id
  end

  test "asks the hub to retry when the JWKS can't be fetched" do
    Privacy::Token.reset_jwks!
    Privacy::Token.stub(:fetch_keys, -> { raise Privacy::Token::Unavailable, "jwks_unavailable" }) do
      post api_privacy_delete_path, headers: { "Authorization" => "Bearer #{privacy_token}" }
    end

    assert_response :service_unavailable
    assert_equal({ "error" => "jwks_unavailable" }, response.parsed_body)
  ensure
    Privacy::Token.reset_jwks!
  end

  test "never logs the token or who it is about" do
    token = privacy_token(request_id: "req-log", subject: { emails: [ @user.email ], slack_id: "U_PRIVACY", identity_id: "hca-U_PRIVACY" })
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)

    Rails.stub(:logger, logger) { call(api_privacy_delete_path, token) }

    assert_includes log.string, "request_id=req-log"
    [ token, @user.email, "U_PRIVACY", "hca-U_PRIVACY" ].each { |secret| assert_not_includes log.string, secret }
  end

  private

  def call(path, token, params: nil)
    with_privacy_jwks do
      post path, params:, headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
    end
  end
end
