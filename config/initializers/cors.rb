Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "*"

    resource "/api/*",
      headers: :any,
      methods: %i[get post patch delete options head],
      expose: %w[X-Request-ID X-DB-Queries X-Cache-Hits X-Cache-Misses],
      max_age: 3600
  end
end
