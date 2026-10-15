require "test_helper"

class Privacy::TokenTest < ActiveSupport::TestCase
  include PrivacyTokenHelper

  def verify(token)
    with_privacy_jwks { Privacy::Token.verify!(token) }
  end

  def assert_rejected(code, token)
    error = assert_raises(Privacy::Token::Invalid) { verify(token) }
    assert_equal code, error.code
  end

  test "accepts a valid token and normalises the subject" do
    claims = verify(privacy_token(dry_run: false, request_id: "req-1", subject: { emails: [ " Someone@Example.com " ], slack_id: "U123" }))

    assert_equal "req-1", claims.request_id
    assert_equal "delete", claims.action
    assert_equal false, claims.dry_run
    assert_equal [ "someone@example.com" ], claims.subject.emails
    assert_equal "U123", claims.subject.slack_id
    assert_nil claims.subject.identity_id
  end

  test "rejects a missing token" do
    assert_rejected "missing_token", nil
  end

  test "rejects a token for another program" do
    assert_rejected "invalid_aud", privacy_token(aud: "flavortown")
    assert_rejected "invalid_aud", privacy_token(aud: [ Privacy::Token::AUDIENCE, "flavortown" ])
  end

  test "rejects the wrong issuer" do
    assert_rejected "invalid_iss", privacy_token(iss: "someone-else")
  end

  test "rejects a token signed by another key" do
    assert_rejected "bad_signature", privacy_token(key: OpenSSL::PKey::EC.generate("prime256v1"))
  end

  test "rejects other algorithms" do
    now = Time.now.to_i
    token = JWT.encode({ iss: "hackclub-privacy", aud: Privacy::Token::AUDIENCE, iat: now, exp: now + 60 }, "secret", "HS256", { kid: PRIVACY_KID, typ: "JWT" })

    assert_rejected "alg_not_allowed", token
  end

  test "rejects a typ other than JWT" do
    assert_rejected "invalid_typ", privacy_token(header: { typ: "at+jwt" })
  end

  test "allows 30 seconds of clock leeway and no more" do
    now = Time.now.to_i

    assert verify(privacy_token(iat: now - 310, exp: now - 20))
    assert_rejected "expired", privacy_token(iat: now - 340, exp: now - 40)
    assert verify(privacy_token(iat: now + 20, exp: now + 200))
    assert_rejected "invalid_iat", privacy_token(iat: now + 60, exp: now + 200)
  end

  test "rejects tokens that live longer than 300 seconds" do
    now = Time.now.to_i

    assert_rejected "invalid_lifetime", privacy_token(iat: now, exp: now + 301)
  end

  test "rejects missing or malformed claims" do
    assert_rejected "invalid_jti", privacy_token(jti: "")
    assert_rejected "invalid_action", privacy_token(action: "purge")
    assert_rejected "invalid_dry_run", privacy_token(dry_run: "false")
    assert_rejected "invalid_subject", privacy_token(subject: { emails: "someone@example.com" })
    assert_rejected "invalid_token", privacy_token(exp: nil)
  end

  test "refetches the JWKS when a token names an unknown key, at most every 30 seconds" do
    rotated = OpenSSL::PKey::EC.generate("prime256v1")
    fetches = 0
    keys = privacy_jwks
    fetch = -> { fetches += 1; keys }

    Privacy::Token.reset_jwks!
    Privacy::Token.stub(:fetch_keys, fetch) do
      Privacy::Token.verify!(privacy_token)
      keys = privacy_jwks(rotated, kid: "rotated")

      error = assert_raises(Privacy::Token::Invalid) { Privacy::Token.verify!(privacy_token(key: rotated, header: { kid: "rotated" })) }
      assert_equal "invalid_token", error.code
      assert_equal 1, fetches

      travel 31.seconds do
        assert Privacy::Token.verify!(privacy_token(key: rotated, header: { kid: "rotated" }))
      end
      assert_equal 2, fetches
    end
  ensure
    Privacy::Token.reset_jwks!
  end

  test "reports an unreachable JWKS as unavailable" do
    Privacy::Token.reset_jwks!
    Privacy::Token.stub(:fetch_keys, -> { raise Privacy::Token::Unavailable, "jwks_unavailable" }) do
      error = assert_raises(Privacy::Token::Unavailable) { Privacy::Token.verify!(privacy_token) }
      assert_equal "jwks_unavailable", error.code
    end
  ensure
    Privacy::Token.reset_jwks!
  end
end
