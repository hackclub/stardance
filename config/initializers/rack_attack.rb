require "rack/attack"

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
