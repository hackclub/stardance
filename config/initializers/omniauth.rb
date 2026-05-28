# Strip query strings from the OAuth2 callback URL. OmniAuth's default
# `callback_url` is `full_host + callback_path + query_string`, which means any
# query param on the auth request (e.g. `?login_hint=…`) gets concatenated into
# the redirect_uri sent to the provider — making it diverge from the URI
# registered on the OAuth app. That mismatch surfaces as `invalid_grant` at
# token exchange.
OmniAuth::Strategies::OAuth2.class_eval do
  def callback_url
    full_host + callback_path
  end
end

Rails.application.config.middleware.use OmniAuth::Builder do
    # Hack Club Account via generic OAuth2
    provider :oauth2,
      Rails.application.credentials.dig(:idv, :client_id),
      Rails.application.credentials.dig(:idv, :client_secret),
      {
        name: :hack_club,
        scope: "openid email name profile verification_status slack_id address phone",
        callback_path: "/oauth/callback",
        client_options: {
          site:         HCAService.host,
          authorize_url: "/oauth/authorize",
          token_url:     "/oauth/token"
        },
        setup: lambda { |env|
          request = Rack::Request.new(env)
          login_hint = request.params["login_hint"]
          if login_hint.present?
            env["omniauth.strategy"].options[:authorize_params] ||= {}
            env["omniauth.strategy"].options[:authorize_params][:login_hint] = login_hint
          end
        }
      }

    provider :oauth2,
      Rails.application.credentials.dig(:hackatime, :client_id),
      Rails.application.credentials.dig(:hackatime, :client_secret),
      {
        name: :hackatime,
        scope: "profile read",
        client_options: {
          site:          "https://hackatime.hackclub.com",
          authorize_url: "/oauth/authorize",
          token_url:     "/oauth/token"
        }
      }
end
