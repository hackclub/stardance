require "rack/attack"
require "ipaddr"

Rack::Attack.cache.store = Rails.cache

module RackAttackClient
  CLOUDFLARE_IP_RANGES = %w[
    173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
    141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20
    197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
    104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
    2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32
    2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32
  ].map { |range| IPAddr.new(range) }.freeze

  STATIC_PATHS = %r{\A/(assets|favicon\.ico|robots\.txt|manifest\.json|apple-touch-icon)}.freeze
  AUTH_PATHS = %r{\A/(auth/[^/]+/callback|oauth/callback|auth/failure)\z}.freeze
  ADMIN_PATHS = %r{\A/admin(/|\z)}.freeze
  API_V1_PROJECTS_PATH = %r{\A/api/v1/projects\z}.freeze
  API_V1_PROJECT_PATH = %r{\A/api/v1/projects/\d+\z}.freeze
  API_V1_PROJECT_DEVLOGS_PATH = %r{\A/api/v1/projects/\d+/devlogs\z}.freeze
  API_V1_DEVLOGS_PATH = %r{\A/api/v1/devlogs\z}.freeze
  API_V1_DEVLOG_PATH = %r{\A/api/v1/devlogs/\d+\z}.freeze

  def self.ip(request)
    cf_ip = request.get_header("HTTP_CF_CONNECTING_IP")
    return cf_ip if cf_ip.present? && cloudflare_proxy?(request)

    request.ip
  end

  def self.cloudflare_proxy?(request)
    peer_ip = IPAddr.new(request.get_header("REMOTE_ADDR"))
    CLOUDFLARE_IP_RANGES.any? { |range| range.include?(peer_ip) }
  rescue IPAddr::InvalidAddressError
    false
  end

  def self.user_or_ip(request)
    user_id = request.session[:user_id]

    user_id.present? ? "user:#{user_id}" : "ip:#{ip(request)}"
  end

  def self.api_client(request)
    request.get_header("HTTP_AUTHORIZATION").to_s[/\ABearer (.+)\z/, 1] || ip(request)
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

Rack::Attack.throttle("requests/ip", limit: 600, period: 5.minutes) do |req|
  RackAttackClient.ip(req) unless RackAttackClient.admin_request?(req)
end

Rack::Attack.throttle("request bursts/ip", limit: 120, period: 1.minute) do |req|
  RackAttackClient.ip(req) unless RackAttackClient.admin_request?(req)
end

Rack::Attack.throttle("state-changing requests/ip", limit: 60, period: 1.minute) do |req|
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

Rack::Attack.throttle("api/v1/projects list", limit: 5, period: 1.minute) do |req|
  RackAttackClient.api_client(req) if req.get? && req.path.match?(RackAttackClient::API_V1_PROJECTS_PATH) && req.params["query"].blank?
end

Rack::Attack.throttle("api/v1/projects search", limit: 20, period: 1.minute) do |req|
  RackAttackClient.api_client(req) if req.get? && req.path.match?(RackAttackClient::API_V1_PROJECTS_PATH) && req.params["query"].present?
end

Rack::Attack.throttle("api/v1/projects show", limit: 30, period: 1.minute) do |req|
  RackAttackClient.api_client(req) if req.get? && req.path.match?(RackAttackClient::API_V1_PROJECT_PATH)
end

Rack::Attack.throttle("api/v1/projects devlogs", limit: 20, period: 1.minute) do |req|
  RackAttackClient.api_client(req) if req.get? && req.path.match?(RackAttackClient::API_V1_PROJECT_DEVLOGS_PATH)
end

Rack::Attack.throttle("api/v1/devlogs list", limit: 5, period: 1.minute) do |req|
  RackAttackClient.api_client(req) if req.get? && req.path.match?(RackAttackClient::API_V1_DEVLOGS_PATH)
end

Rack::Attack.throttle("api/v1/devlogs show", limit: 30, period: 1.minute) do |req|
  RackAttackClient.api_client(req) if req.get? && req.path.match?(RackAttackClient::API_V1_DEVLOG_PATH)
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
