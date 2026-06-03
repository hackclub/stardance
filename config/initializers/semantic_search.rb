# frozen_string_literal: true

Rails.application.config.x.semantic_search = ActiveSupport::OrderedOptions.new
Rails.application.config.x.semantic_search.redis = {
  url: ENV["SEARCH_REDIS_URL"].presence,
  reconnect_attempts: 2,
  read_timeout: 1.0,
  error_handler: ->(method:, returning:, exception:) {
    if defined?(Sentry)
      Sentry.capture_exception(
        exception,
        level: "warning",
        tags: { method: method, returning: returning }
      )
    end
  }
}
Rails.application.config.x.semantic_search.openai_api_key =
  Rails.application.credentials.dig(:openai, :api_key).presence
Rails.application.config.x.semantic_search.embedding_model =
  ENV["SEARCH_EMBEDDING_MODEL"].presence || "text-embedding-3-small"
Rails.application.config.x.semantic_search.embedding_dimensions =
  (ENV["SEARCH_EMBEDDING_DIMENSIONS"].presence || 1536).to_i
Rails.application.config.x.semantic_search.result_cache_ttl =
  (ENV["SEARCH_RESULT_CACHE_TTL"].presence || 60).to_i
