module ExternalDashboard
  module AlertThrottle
    extend self

    def once(key, ttl:)
      return if Rails.cache.exist?(key)

      Rails.cache.write(key, true, expires_in: ttl)
      yield
    end
  end
end
