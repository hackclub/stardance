require "net/http"

module Privacy
  # Verifies the ES256 tokens the Hack Club privacy hub signs, against the hub's published JWKS.
  # The endpoints act on these claims only, never on the request body. See docs/privacy.md.
  class Token
    ISSUER = "hackclub-privacy".freeze
    # must match the audience hub staff set for this program, character for character
    AUDIENCE = "stardance".freeze
    # PRIVACY_JWKS_URL only exists to point local development at a local hub
    JWKS_URL = ENV.fetch("PRIVACY_JWKS_URL", "https://yeet.hackclub.com/.well-known/jwks.json").freeze
    ACTIONS = %w[delete export].freeze
    MAX_LIFETIME = 300
    LEEWAY = 30
    JWKS_TTL = 300
    UNKNOWN_KID_REFETCH = 30
    JWT_ERRORS = { JWT::ExpiredSignature => "expired", JWT::IncorrectAlgorithm => "alg_not_allowed", JWT::VerificationError => "bad_signature" }.freeze

    class Invalid < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super("privacy token rejected: #{code}")
      end
    end

    # the JWKS couldn't be fetched, so the hub should retry
    class Unavailable < Invalid; end

    Claims = Data.define(:request_id, :jti, :action, :dry_run, :subject)
    Subject = Data.define(:emails, :slack_id, :identity_id)

    @mutex = Mutex.new
    @jwks = nil
    @fetched_at = nil

    class << self
      def verify!(token, now: Time.now.to_i)
        raise Invalid, "missing_token" if token.blank?

        payload, header = JWT.decode(token, nil, true,
                                     algorithms: [ "ES256" ], jwks: method(:jwks),
                                     leeway: LEEWAY, verify_iat: false, required_claims: %w[exp iat])
        raise Invalid, "invalid_typ" unless header["typ"] == "JWT"

        check_claims!(payload, now)
        build(payload)
      rescue JWT::DecodeError => e
        raise Invalid, JWT_ERRORS.find { |error, _| e.is_a?(error) }&.last || "invalid_token"
      end

      # drops the cached keys, for tests
      def reset_jwks!
        @mutex.synchronize { @jwks = @fetched_at = nil }
      end

      private

      def check_claims!(claims, now)
        raise Invalid, "invalid_iss" unless claims["iss"] == ISSUER
        raise Invalid, "invalid_aud" unless claims["aud"] == AUDIENCE

        iat = claims["iat"]
        exp = claims["exp"]
        raise Invalid, "invalid_lifetime" unless iat.is_a?(Integer) && exp.is_a?(Integer) && exp - iat <= MAX_LIFETIME
        raise Invalid, "invalid_iat" if iat - LEEWAY > now
        raise Invalid, "invalid_jti" unless claims["jti"].is_a?(String) && claims["jti"].present?
        raise Invalid, "invalid_request_id" unless claims["request_id"].is_a?(String) && claims["request_id"].present?
        raise Invalid, "invalid_action" unless ACTIONS.include?(claims["action"])
        raise Invalid, "invalid_dry_run" unless [ true, false ].include?(claims["dry_run"])
      end

      def build(claims)
        subject = claims["subject"]
        raise Invalid, "invalid_subject" unless subject.is_a?(Hash)

        emails, slack_id, identity_id = subject.values_at("emails", "slack_id", "identity_id")
        valid = emails.is_a?(Array) && emails.all? { |email| present_string?(email) } &&
          (slack_id.nil? || present_string?(slack_id)) && (identity_id.nil? || present_string?(identity_id))
        raise Invalid, "invalid_subject" unless valid

        Claims.new(
          request_id: claims["request_id"],
          jti: claims["jti"],
          action: claims["action"],
          dry_run: claims["dry_run"],
          subject: Subject.new(emails: emails.map { |email| email.strip.downcase }.uniq, slack_id:, identity_id:)
        )
      end

      def present_string?(value) = value.is_a?(String) && value.present?

      # ruby-jwt calls this with kid_not_found: true when the token names a key we don't have
      def jwks(options)
        @mutex.synchronize do
          refresh! if @fetched_at.nil? || Time.now - @fetched_at > JWKS_TTL
          refresh! if options[:kid_not_found] && Time.now - @fetched_at > UNKNOWN_KID_REFETCH
          @jwks
        end
      end

      def refresh!
        @jwks = JWT::JWK::Set.new("keys" => fetch_keys.select { |jwk| usable?(jwk) })
        @fetched_at = Time.now
      rescue JWT::JWKError, ArgumentError
        raise Unavailable, "jwks_unavailable"
      end

      def fetch_keys
        uri = URI(JWKS_URL)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 5) do |http|
          http.get(uri.request_uri, "Accept" => "application/json")
        end
        raise Unavailable, "jwks_unavailable" unless response.is_a?(Net::HTTPSuccess)

        body = JSON.parse(response.body)
        keys = body["keys"] if body.is_a?(Hash)
        raise Unavailable, "jwks_unavailable" unless keys.is_a?(Array)

        keys
      rescue JSON::ParserError, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Timeout::Error
        raise Unavailable, "jwks_unavailable"
      end

      def usable?(jwk)
        jwk.is_a?(Hash) && jwk["kty"] == "EC" && jwk["crv"] == "P-256" && present_string?(jwk["kid"]) &&
          [ nil, "ES256" ].include?(jwk["alg"]) && [ nil, "sig" ].include?(jwk["use"])
      end
    end
  end
end
