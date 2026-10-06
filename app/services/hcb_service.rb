class HCBError < StandardError; end
class HCBUnauthorizedError < HCBError; end

# Middleware: raise specific error for 401 so we can refresh + retry,
# and raise generic HCBError for other non-success responses.
class RaiseHCBErrorMiddleware < Faraday::Middleware
  def on_complete(env)
    status = env.status
    body = env.body

    if status == 401
      raise HCBUnauthorizedError, "HCB returned 401: #{body}"
    end

    raise HCBError, "HCB returned #{status}: #{body}" unless env.response.success?
  end
end

Faraday::Response.register_middleware hcb_error: RaiseHCBErrorMiddleware

module HCBService
  DEFAULT_BASE_URL = "https://hcb.hackclub.com"
  DEFAULT_SLUG = "stardance"

  # HCB issues access tokens with a two-hour life (`access_token_expires_in` in
  # its Doorkeeper config). Refresh this far ahead of the recorded expiry so a
  # request that starts just before the boundary still finishes with a live
  # token, instead of discovering the expiry as a 401 mid-flight.
  EXPIRY_MARGIN = 5.minutes

  class << self
    def base_url
      HCBCredential.first&.base_url.presence || DEFAULT_BASE_URL
    end

    def slug
      HCBCredential.first&.slug.presence || DEFAULT_SLUG
    end

    # A development database has no HCB tokens, so every call goes out to the
    # real HCB with a blank bearer token, comes back 401, and then dies in the
    # refresh. Answer locally instead, so the hardware and shop flows can be
    # exercised without a live grant. Storing real credentials in development
    # switches this back off, and it never applies outside development: test
    # stubs the service, and production must fail loudly.
    def simulated?
      Rails.env.development? && HCBCredential.first&.refresh_token.blank?
    end

    # Refreshes ahead of a known expiry, then falls back to refresh-and-retry if
    # HCB rejects the token anyway (the expiry is unknown on a credential that
    # has never been refreshed through here, and a token can be revoked early).
    def with_retry
      # Best effort: the token hasn't necessarily expired yet, so a transient
      # failure here shouldn't sink a request that would have gone through. The
      # 401 path below is the real backstop.
      if refresh_due?
        begin
          refresh_token!
        rescue HCBError => e
          Rails.logger.warn "HCB proactive token refresh failed, continuing with the current token: #{e.message}"
        end
      end

      attempts = 0
      begin
        yield
      rescue HCBUnauthorizedError
        attempts += 1
        if attempts <= 1 && refresh_token!
          retry
        end
        raise
      end
    end

    # Nil when no refresh has recorded an expiry yet, which leaves the 401 path
    # above as the only trigger rather than refreshing on every single call.
    def refresh_due?
      expires_at = HCBCredential.first&.expires_at
      expires_at.present? && expires_at <= EXPIRY_MARGIN.from_now
    end

    def refresh_token!
      hcb_credentials = HCBCredential.first
      raise HCBError, "no HCB credentials found" unless hcb_credentials

      # The token we held when we decided a refresh was needed, captured before
      # the lock so it can be compared against what the previous lock holder
      # left behind. See the skip below for why that matters.
      access_token_before = hcb_credentials.access_token

      # Lock the row before reading the refresh token. HCB refresh tokens are
      # single-use and rotate on every refresh, so if two requests race here,
      # whoever reads the token first (before the winner's update commits)
      # submits an already-consumed token and gets invalid_grant. Locking
      # forces the loser to wait, then `with_lock` reloads the record so it
      # reads the winner's freshly-rotated token instead of a stale one.
      hcb_credentials.with_lock do
        # Locking alone only serialises refreshes, it doesn't collapse them, and
        # a second refresh is actively harmful: HCB revokes the previous access
        # token every time one succeeds (its api_tokens table has no
        # previous_refresh_token column, so Doorkeeper's revoke-on-use grace
        # window doesn't apply). Refreshing again here would revoke the token
        # the winner just stored and send it straight back with a 401, and the
        # two would take turns invalidating each other. The reload above means a
        # moved token is proof someone else already did this work.
        next true if hcb_credentials.access_token.present? &&
                     hcb_credentials.access_token != access_token_before

        client_id = hcb_credentials.client_id
        client_secret = hcb_credentials.client_secret
        refresh_token = hcb_credentials.refresh_token
        redirect_uri = hcb_credentials.redirect_uri
        base = hcb_credentials.base_url.presence || DEFAULT_BASE_URL

        # Without this the request goes out with a blank token and HCB answers a
        # bare `invalid_request`, which reads like a transient API fault rather
        # than "someone has to re-authorize HCB".
        if refresh_token.blank?
          raise HCBError, "no refresh token stored - re-authorize HCB and update HCBCredential"
        end

        # Use a lightweight connection to call the token endpoint to avoid recursion.
        # Doorkeeper expects a form-encoded POST (application/x-www-form-urlencoded).
        token_conn = Faraday.new(url: "#{base}/api/v4/") do |f|
          f.request :url_encoded
          f.response :json, content_type: /\bjson$/
          f.adapter :net_http
          f.headers["Accept"] = "application/json"
          # Bounded so a hung HCB request can't hold the row lock open indefinitely.
          f.options.open_timeout = 5
          f.options.timeout = 10
        end

        message = {
          client_id: client_id,
          client_secret: client_secret,
          refresh_token: refresh_token,
          redirect_uri: redirect_uri,
          grant_type: "refresh_token"
        }

        # Send form-encoded params (not JSON) so Doorkeeper accepts the refresh request.
        resp = token_conn.post("oauth/token", message)

        raise HCBError, refresh_failure_message(resp) unless resp.success?

        body = resp.body
        access_token = body && (body["access_token"] || body[:access_token])
        new_refresh_token = body && (body["refresh_token"] || body[:refresh_token])
        expires_in = body && (body["expires_in"] || body[:expires_in])
        raise HCBError, "no access_token in response: #{body}" unless access_token

        # A refresh_token is OPTIONAL in a refresh response (RFC 6749 §5.1): a
        # provider that doesn't rotate them just omits it. Writing it back
        # unconditionally therefore erases the one we still need, and every later
        # refresh then posts a blank token and gets `invalid_request` back, with
        # no way to recover except re-authorizing by hand.
        attrs = { access_token: access_token }
        attrs[:refresh_token] = new_refresh_token if new_refresh_token.present?

        # Cleared rather than left stale when HCB omits expires_in, so a missing
        # lifetime falls back to refreshing on 401 instead of pinning expires_at
        # in the past and refreshing before every call.
        attrs[:expires_at] = expires_in.present? ? expires_in.to_i.seconds.from_now : nil

        # HCB has already rotated the refresh token server-side, so the tokens in
        # this response are the only ones that still work. Losing them here means
        # the credential can only be recovered by re-authorizing HCB by hand, so
        # page someone rather than letting it surface as an ordinary API error.
        begin
          hcb_credentials.update!(attrs)
        rescue => e
          OperationalAlert.report(
            "HCB token refresh succeeded but failed to persist new tokens - credentials are now bricked",
            severity: :error,
            context: { error: e.message }
          )
          raise HCBError, "refreshed HCB tokens but failed to save them: #{e.message}"
        end

        true
      end
    rescue Faraday::Error => e
      raise HCBError, "token refresh HTTP error: #{e.message}"
    rescue HCBError
      raise
    rescue => e
      raise HCBError, "token refresh failed: #{e.message}"
    end

    # `invalid_grant` means the stored refresh token is gone for good - already
    # consumed by an earlier refresh, or revoked on HCB's side. Retrying can
    # never fix it, so name the one thing that will instead of reporting it the
    # same way as a transient HCB fault.
    def refresh_failure_message(resp)
      error = resp.body.is_a?(Hash) ? resp.body["error"] || resp.body[:error] : resp.body

      if error.to_s == "invalid_grant"
        "HCB rejected the stored refresh token (invalid_grant) - re-authorize HCB and update HCBCredential"
      else
        "token refresh failed with status #{resp.status}: #{error}"
      end
    end

    def create_card_grant(email:, amount_cents:, merchant_lock: nil, category_lock: nil, keyword_lock: nil, purpose: nil, pre_authorization_required: false, one_time_use: false, instructions: nil, organization: nil)
      return simulate(:create_card_grant, amount_cents: amount_cents) if simulated?

      with_retry do
        org = organization || slug
        conn.post("organizations/#{org}/card_grants", email:, amount_cents:, category_lock:, merchant_lock:, keyword_lock:, purpose:, pre_authorization_required:, one_time_use:, instructions:).body
      end
    end

    def topup_card_grant(hashid:, amount_cents:)
      Rails.logger.info "Topping up HCB card grant #{hashid} by #{amount_cents}¢"
      return simulate(:topup_card_grant, hashid: hashid, amount_cents: amount_cents) if simulated?

      with_retry { conn.post("card_grants/#{hashid}/topup", amount_cents:).body }
    end

    def rename_transaction(hashid:, new_memo:)
      return simulate(:rename_transaction, hashid: hashid) if simulated?

      with_retry { conn.put("organizations/#{slug}/transactions/#{hashid}", memo: new_memo).body }
    end

    def show_card_grant(hashid:)
      return simulate(:show_card_grant, hashid: hashid) if simulated?

      with_retry { conn.get("card_grants/#{hashid}?expand=balance_cents,disbursements").body }
    end

    def update_card_grant(hashid:, merchant_lock: nil, category_lock: nil, keyword_lock: nil, purpose: nil, instructions: nil)
      return simulate(:update_card_grant, hashid: hashid) if simulated?

      with_retry { conn.patch("card_grants/#{hashid}", { merchant_lock:, category_lock:, keyword_lock:, purpose:, instructions: }.compact).body }
    end

    def show_stripe_card(hashid:)
      return simulate(:show_stripe_card, hashid: hashid) if simulated?

      with_retry { conn.get("cards/#{hashid}").body }
    end

    def cancel_card_grant!(hashid:)
      return simulate(:cancel_card_grant!, hashid: hashid, status: "canceled") if simulated?

      with_retry { conn.post("card_grants/#{hashid}/cancel").body }
    end

    def index_card_grants
      return [] if simulated?

      with_retry { conn.get("organizations/#{slug}/card_grants").body }
    end

    # Stand-in for an HCB response body, shaped like the real one: callers read
    # `["id"]`, `["status"]` and `dig("disbursements", 0, "transaction_id")`, and
    # ShopCardGrant#stripped_hashid drops a four-character prefix off the hashid.
    def simulate(call, hashid: nil, amount_cents: 0, status: "active")
      hashid ||= "cdg_dev#{SecureRandom.hex(5)}"
      Rails.logger.info "[HCB simulated] #{call} -> #{hashid} (no HCB credentials in development)"

      Hashie::Mash.new(
        "id" => hashid,
        "status" => status,
        "amount_cents" => amount_cents,
        "balance_cents" => amount_cents,
        "disbursements" => [ { "transaction_id" => "txn_dev#{SecureRandom.hex(5)}" } ]
      )
    end

    # Builds a Faraday connection for the HCB API, using the Bearer token from
    # HCBCredential for OAuth authentication.
    #
    # Deliberately built per call rather than memoized. The access token is baked
    # into the Authorization header, and HCB revokes the previous one every time
    # anybody refreshes - including a web worker refreshing while a job worker is
    # mid-request. A memoized connection keeps presenting a token HCB has already
    # revoked, and invalidating it on refresh only ever reached the one process
    # that did the refreshing, so every other process sat on a dead token until
    # its own 401 sent it off to refresh and revoke everyone else's in turn.
    # Rebuilding is cheap next to the request it wraps, and the credential row
    # was being read on every call regardless.
    def conn
      hcb_creds = HCBCredential.first
      raise HCBError, "no HCB credentials found" unless hcb_creds

      Faraday.new url: "#{hcb_creds.base_url.presence || DEFAULT_BASE_URL}/api/v4/" do |faraday|
        faraday.request :json
        faraday.response :mashify
        faraday.response :json
        faraday.response :hcb_error
        faraday.headers["Authorization"] = "Bearer #{hcb_creds.access_token}"
      end
    end
  end
end
