# Signs privacy hub tokens with a throwaway key and serves it as the hub's JWKS.
module PrivacyTokenHelper
  PRIVACY_KEY = OpenSSL::PKey::EC.generate("prime256v1")
  PRIVACY_KID = "test-key".freeze

  def privacy_jwks(key = PRIVACY_KEY, kid: PRIVACY_KID)
    [ JWT::JWK.new(key, kid:).export.transform_keys(&:to_s) ]
  end

  def privacy_token(action: "delete", dry_run: true, subject: {}, key: PRIVACY_KEY, header: {}, **claims)
    now = Time.now.to_i
    payload = {
      iss: "hackclub-privacy", aud: Privacy::Token::AUDIENCE, iat: now, exp: now + 300,
      jti: SecureRandom.uuid, request_id: SecureRandom.uuid, action:, dry_run:,
      subject: { emails: [], slack_id: nil, identity_id: nil }.merge(subject)
    }.merge(claims).compact
    JWT.encode(payload, key, "ES256", { kid: PRIVACY_KID, typ: "JWT" }.merge(header))
  end

  def with_privacy_jwks(keys = privacy_jwks, &block)
    Privacy::Token.reset_jwks!
    Privacy::Token.stub(:fetch_keys, keys, &block)
  ensure
    Privacy::Token.reset_jwks!
  end
end
