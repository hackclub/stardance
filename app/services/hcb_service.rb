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
  class << self
    def base_url
      hcb_credentials = HCBCredential.first
      hcb_credentials&.base_url.presence || "https://hcb.hackclub.com"
    end

    def slug
      hcb_credentials = HCBCredential.first
      hcb_credentials&.slug.presence || "stardance"
    end

    # Generic wrapper that will attempt a token refresh on 401 once, then retry.
    def with_retry
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

    def refresh_token!
      HCBCredential.transaction do
        hcb_credentials = HCBCredential.first
        raise HCBError, "no HCB credentials found" unless hcb_credentials
        client_id = hcb_credentials.client_id
        client_secret = hcb_credentials.client_secret
        refresh_token = hcb_credentials.refresh_token
        redirect_uri = hcb_credentials.redirect_uri
        base = hcb_credentials.base_url || base_url

        # Use a lightweight connection to call the token endpoint to avoid recursion.
        # Doorkeeper expects a form-encoded POST (application/x-www-form-urlencoded).
        token_conn = Faraday.new(url: "#{base}/api/v4/") do |f|
          f.request :url_encoded
          f.response :json, content_type: /\bjson$/
          f.adapter :net_http
          f.headers["Accept"] = "application/json"
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

        unless resp.success?
          error_msg = resp.body.is_a?(Hash) ? resp.body["error"] || resp.body[:error] : resp.body
          raise HCBError, "token refresh failed with status #{resp.status}: #{error_msg}"
        end

        body = resp.body
        access_token = body && (body["access_token"] || body[:access_token])
        new_refresh_token = body && (body["refresh_token"] || body[:refresh_token])
        raise HCBError, "no access_token in response: #{body}" unless access_token

        hcb_credentials.update!(refresh_token: new_refresh_token, access_token: access_token)
        @conn = nil

        true
      rescue Faraday::Error => e
        raise HCBError, "token refresh HTTP error: #{e.message}"
      rescue => e
        raise HCBError, "token refresh failed: #{e.message}"
      end
    end

    def create_card_grant(email:, amount_cents:, merchant_lock: nil, category_lock: nil, keyword_lock: nil, purpose: nil, pre_authorization_required: false, one_time_use: false, instructions: nil)
      with_retry do
        conn.post("organizations/#{@hcb_org_slug}/card_grants", email:, amount_cents:, category_lock:, merchant_lock:, keyword_lock:, purpose:, pre_authorization_required:, one_time_use:, instructions:).body
      end
    end

    def topup_card_grant(hashid:, amount_cents:)
      Rails.logger.info "Topping up HCB card grant #{hashid} by #{amount_cents}¢"
      with_retry { conn.post("card_grants/#{hashid}/topup", amount_cents:).body }
    end

    def rename_transaction(hashid:, new_memo:)
      with_retry { conn.put("organizations/#{@hcb_org_slug}/transactions/#{hashid}", memo: new_memo).body }
    end

    def show_card_grant(hashid:)
      with_retry { conn.get("card_grants/#{hashid}?expand=balance_cents,disbursements").body }
    end

    def update_card_grant(hashid:, merchant_lock: nil, category_lock: nil, keyword_lock: nil, purpose: nil, instructions: nil)
      with_retry { conn.patch("card_grants/#{hashid}", { merchant_lock:, category_lock:, keyword_lock:, purpose:, instructions: }.compact).body }
    end

    def show_stripe_card(hashid:)
      with_retry { conn.get("cards/#{hashid}").body }
    end

    def cancel_card_grant!(hashid:)
      with_retry { conn.post("card_grants/#{hashid}/cancel").body }
    end

    def index_card_grants
      with_retry { conn.get("organizations/#{@hcb_org_slug}/card_grants").body }
    end

    # Builds (or returns cached) Faraday connection for HCB API.
    # Uses Bearer token from HCBCredential for OAuth authentication.
    def conn
      hcb_creds = HCBCredential.first
      raise HCBError, "no HCB credentials found" unless hcb_creds
      hcb_access_token = hcb_creds.access_token
      @hcb_org_slug = hcb_creds.slug

      @conn ||= Faraday.new url: "#{hcb_creds.base_url || base_url}/api/v4/" do |faraday|
        faraday.request :json
        faraday.response :mashify
        faraday.response :json
        faraday.response :hcb_error
        faraday.headers["Authorization"] = "Bearer #{hcb_access_token}"
      end
    end
  end
end
