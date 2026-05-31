require "rack/attack"

Rack::Attack.throttle("api/ip", limit: 50, period: 1.minute) do |req|
  req.ip if req.path.start_with?("/api/")
end

Rack::Attack.throttle("api/token", limit: 50, period: 1.minute) do |req|
  req.get_header("HTTP_AUTHORIZATION")&.delete_prefix("Bearer ")&.strip.presence if req.path.start_with?("/api/")
end

Rack::Attack.throttled_responder = lambda do |req|
  body = {
    error: "rate_limited",
    message: "Too many requests. Please slow down."
  }.to_json

  [
    429,
    {
      "Content-Type" => "application/json",
      "Retry-After" => req.env["rack.attack.match_data"][:period].to_s
    },
    [ body ]
  ]
end
