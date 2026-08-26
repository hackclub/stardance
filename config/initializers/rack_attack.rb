require "rack/attack"

Rack::Attack.cache.store = Rails.cache

module RackAttackClient
  STATIC_PATHS = %r{\A/(assets|favicon\.ico|robots\.txt|manifest\.json|apple-touch-icon)}.freeze
  AUTH_PATHS = %r{\A/(auth/[^/]+/callback|oauth/callback|auth/failure)\z}.freeze
  ADMIN_PATHS = %r{\A/admin(/|\z)}.freeze

  def self.ip(request)
    request.get_header("HTTP_CF_CONNECTING_IP").presence || request.ip
  end

  def self.user_or_ip(request)
    user_id = request.session[:user_id]

    user_id.present? ? "user:#{user_id}" : "ip:#{ip(request)}"
  end

  def self.static_request?(request)
    request.path.match?(STATIC_PATHS)
  end

  def self.health_check?(request)
    request.path == "/up"
  end

  def self.auth_request?(request)
    request.path.match?(AUTH_PATHS)
  end

  def self.admin_request?(request)
    request.path.match?(ADMIN_PATHS)
  end
end

Rack::Attack.safelist("allow health checks") do |req|
  RackAttackClient.health_check?(req)
end

Rack::Attack.safelist("allow static assets") do |req|
  RackAttackClient.static_request?(req)
end

Rack::Attack.throttle("requests/ip", limit: 1200, period: 5.minutes) do |req|
  RackAttackClient.ip(req) unless RackAttackClient.admin_request?(req)
end

Rack::Attack.throttle("request bursts/ip", limit: 480, period: 1.minute) do |req|
  RackAttackClient.ip(req) unless RackAttackClient.admin_request?(req)
end

Rack::Attack.throttle("state-changing requests/ip", limit: 120, period: 1.minute) do |req|
  RackAttackClient.ip(req) if !(req.get? || req.head? || req.options?) && !RackAttackClient.admin_request?(req)
end

Rack::Attack.throttle("admin requests/ip", limit: 1500, period: 5.minutes) do |req|
  RackAttackClient.ip(req) if RackAttackClient.admin_request?(req)
end

Rack::Attack.throttle("admin request bursts/ip", limit: 300, period: 1.minute) do |req|
  RackAttackClient.ip(req) if RackAttackClient.admin_request?(req)
end

Rack::Attack.throttle("admin state-changing requests/ip", limit: 180, period: 1.minute) do |req|
  RackAttackClient.ip(req) if RackAttackClient.admin_request?(req) && !(req.get? || req.head? || req.options?)
end

Rack::Attack.throttle("auth callbacks/ip", limit: 20, period: 5.minutes) do |req|
  RackAttackClient.ip(req) if RackAttackClient.auth_request?(req)
end

Rack::Attack.throttle("user follows", limit: 10, period: 1.minute) do |req|
  RackAttackClient.user_or_ip(req) if req.post? && req.path.match?(%r{\A/users/[^/]+/follow\z})
end

Rack::Attack.throttle("project follows", limit: 10, period: 1.minute) do |req|
  RackAttackClient.user_or_ip(req) if req.post? && req.path.match?(%r{\A/projects/[^/]+/follow\z})
end

Rack::Attack.throttle("devlog likes", limit: 30, period: 1.minute) do |req|
  RackAttackClient.user_or_ip(req) if req.post? && req.path.match?(%r{\A/devlogs/[^/]+/like\z})
end

Rack::Attack.throttle("devlog comments", limit: 5, period: 1.minute) do |req|
  RackAttackClient.user_or_ip(req) if req.post? && req.path.match?(%r{\A/devlogs/[^/]+/comments\z})
end

Rack::Attack.throttle("post reposts", limit: 10, period: 1.minute) do |req|
  RackAttackClient.user_or_ip(req) if req.post? && req.path.match?(%r{\A/posts/[^/]+/repost\z})
end

Rack::Attack.throttled_responder = lambda do |req|
  match_data = req.env["rack.attack.match_data"] || {}
  retry_after = match_data.fetch(:period, 60).to_s

  body = {
    error: "rate_limited",
    message: "Too many requests. Please slow down."
  }.to_json

  [
    429,
    {
      "Content-Type" => "application/json",
      "Retry-After" => retry_after
    },
    [ body ]
  ]
end
