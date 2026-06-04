# frozen_string_literal: true

module SemanticSearch
  INDEX_NAME = "stardance_semantic_search"
  DOC_PREFIX = "search:doc:"
  CACHE_PREFIX = "search:results:"
  DEFAULT_MODEL = "text-embedding-3-small"
  DEFAULT_DIMENSIONS = 512
  DEFAULT_RESULT_CACHE_TTL = 60

  TYPES = %w[project devlog ship user].freeze

  class Error < StandardError; end

  class << self
    def enabled?
      redis_url.present? && openai_api_key.present?
    end

    def model = config.embedding_model.presence || DEFAULT_MODEL

    def dimensions = (config.embedding_dimensions.presence || DEFAULT_DIMENSIONS).to_i

    def result_cache_ttl = (config.result_cache_ttl.presence || DEFAULT_RESULT_CACHE_TTL).to_i

    def redis_url = redis_config[:url].presence

    def openai_api_key
      config.openai_api_key.presence
    end

    def redis = @redis ||= Redis.new(**redis_client_options)

    def reset_connections!
      @redis&.close
      @redis = nil
      @openai_connection = nil
    end

    def ensure_index!
      return false unless redis_url.present?

      redis.call("FT.INFO", INDEX_NAME)
      true
    rescue Redis::CommandError => e
      raise unless e.message.match?(/Unknown Index name|no such index/i)

      redis.call(
        "FT.CREATE", INDEX_NAME,
        "ON", "HASH",
        "PREFIX", "1", DOC_PREFIX,
        "SCHEMA",
        "type", "TAG",
        "record_key", "TAG",
        "title", "TEXT", "WEIGHT", "3.0",
        "subtitle", "TEXT", "WEIGHT", "1.5",
        "preview", "TEXT",
        "path", "TEXT", "NOINDEX",
        "updated_at", "NUMERIC", "SORTABLE",
        "embedding", "VECTOR", "HNSW", "6",
        "TYPE", "FLOAT32",
        "DIM", dimensions.to_s,
        "DISTANCE_METRIC", "COSINE"
      )
      true
    rescue Redis::BaseError => e
      handle_redis_error(:ensure_index, false, e)
      Rails.logger.warn("SemanticSearch index unavailable: #{e.class}: #{e.message}")
      false
    end

    def upsert(record)
      document = Document.for(record)
      unless document&.indexable?
        delete(record)
        return false
      end
      return false unless enabled? && ensure_index!

      vector = embed(document.search_text)
      return false if vector.blank?

      redis.mapped_hmset(
        document.redis_key,
        document.to_redis_hash.merge("embedding" => pack_vector(vector))
      )
      clear_result_cache
      true
    rescue StandardError => e
      handle_redis_error(:upsert, false, e) if e.is_a?(Redis::BaseError)
      Rails.logger.warn("SemanticSearch upsert failed for #{record.class.name}##{record.id}: #{e.class}: #{e.message}")
      false
    end

    def upsert_batch(records, batch_size: 100)
      return 0 unless enabled? && ensure_index!

      indexed = 0

      records.each_slice(batch_size) do |batch|
        docs = batch.filter_map { |record| Document.for(record) }.select(&:indexable?)
        next if docs.empty?

        vectors = embed_many(docs.map(&:search_text))
        next if vectors.blank?

        redis.pipelined do |pipe|
          docs.zip(vectors).each do |doc, vector|
            next if vector.blank?
            pipe.mapped_hmset(doc.redis_key, doc.to_redis_hash.merge("embedding" => pack_vector(vector)))
            indexed += 1
          end
        end
      end

      clear_result_cache
      indexed
    rescue StandardError => e
      handle_redis_error(:upsert_batch, 0, e) if e.is_a?(Redis::BaseError)
      Rails.logger.warn("SemanticSearch upsert_batch failed: #{e.class}: #{e.message}")
      indexed
    end

    def delete(record_or_type, id = nil)
      type, record_id =
        if record_or_type.respond_to?(:id)
          [ Document.type_for(record_or_type), record_or_type.id ]
        else
          [ record_or_type.to_s, id ]
        end

      return false if type.blank? || record_id.blank? || redis_url.blank?

      redis.del(Document.redis_key_for(type, record_id))
      clear_result_cache
      true
    rescue Redis::BaseError => e
      handle_redis_error(:delete, false, e)
      Rails.logger.warn("SemanticSearch delete failed for #{type}:#{record_id}: #{e.class}: #{e.message}")
      false
    end

    def search(query, viewer:, surface:, limit: 6)
      normalized = query.to_s.squish
      return empty_results if normalized.blank?

      cache_key = cache_key_for(normalized, viewer, surface, limit)
      cached = read_cache(cache_key)
      return cached if cached

      results = search_without_cache(normalized, viewer: viewer, limit: limit)
      write_cache(cache_key, results)
      results
    end

    def search_without_cache(query, viewer:, limit:)
      return empty_results unless enabled? && ensure_index!

      vector = embed(query)
      return empty_results if vector.blank?

      raw = redis.call(
        "FT.SEARCH", INDEX_NAME,
        "*=>[KNN #{limit * 8} @embedding $vec AS distance]",
        "PARAMS", "2", "vec", pack_vector(vector),
        "SORTBY", "distance",
        "RETURN", "8", "type", "record_key", "title", "subtitle", "preview", "path", "updated_at", "distance",
        "DIALECT", "2"
      )

      hydrate(raw, viewer: viewer, limit: limit, query: query)
    rescue Redis::BaseError, Faraday::Error, JSON::ParserError => e
      handle_redis_error(:search, empty_results, e) if e.is_a?(Redis::BaseError)
      Rails.logger.warn("SemanticSearch query failed: #{e.class}: #{e.message}")
      empty_results
    end

    def embed(input)
      response = openai_connection.post do |req|
        req.headers["Authorization"] = "Bearer #{openai_api_key}"
        req.headers["Content-Type"] = "application/json"
        req.body = { model: model, input: input, dimensions: dimensions }.to_json
      end

      raise Error, "OpenAI embeddings error #{response.status}: #{response.body}" unless response.success?

      JSON.parse(response.body).dig("data", 0, "embedding")
    end

    def embed_many(inputs)
      response = openai_connection.post do |req|
        req.headers["Authorization"] = "Bearer #{openai_api_key}"
        req.headers["Content-Type"] = "application/json"
        req.body = { model: model, input: inputs, dimensions: dimensions }.to_json
      end

      raise Error, "OpenAI embeddings error #{response.status}: #{response.body}" unless response.success?

      JSON.parse(response.body)
        .fetch("data", [])
        .sort_by { |d| d["index"] }
        .map { |d| d["embedding"] }
    end

    def openai_connection
      @openai_connection ||= Faraday.new(url: "https://api.openai.com/v1/embeddings") do |f|
        f.request :json
        f.response :raise_error
      end
    end

    def pack_vector(vector)
      vector.map(&:to_f).pack("e*")
    end

    def empty_results
      TYPES.index_with { [] }
    end

    def clear_result_cache
      return unless redis_url.present?

      cursor = "0"
      loop do
        cursor, keys = redis.scan(cursor, match: "#{CACHE_PREFIX}*", count: 100)
        redis.del(*keys) if keys.any?
        break if cursor == "0"
      end
    rescue Redis::BaseError => e
      handle_redis_error(:clear_result_cache, false, e)
      false
    end

    private

    def config
      Rails.application.config.x.semantic_search
    end

    def redis_config
      config.redis || {}
    end

    def redis_client_options
      redis_config.except(:error_handler).compact
    end

    def handle_redis_error(method, returning, exception)
      redis_config[:error_handler]&.call(method: method, returning: returning, exception: exception)
    end

    def hydrate(raw, viewer:, limit:, query: nil)
      rows = parse_redis_search(raw)
      grouped = rows.group_by { |row| row["type"] }
      results = empty_results

      results["project"] = hydrate_projects(grouped["project"], limit, query)
      results["devlog"] = hydrate_devlogs(grouped["devlog"], viewer, limit, query)
      results["ship"] = hydrate_ships(grouped["ship"], viewer, limit, query)
      results["user"] = hydrate_users(grouped["user"], viewer, limit, query)

      results
    end

    def parse_redis_search(raw)
      return [] unless raw.is_a?(Array)

      raw.drop(1).each_slice(2).filter_map do |key, fields|
        next unless key.to_s.start_with?(DOC_PREFIX)

        fields.each_slice(2).to_h
      end
    end

    def hydrate_projects(rows, limit, query = nil)
      ids = ids_from(rows)
      return [] if ids.empty?

      records = Project.not_deleted.where(id: ids).index_by { |project| project.id.to_s }
      results = ids.filter_map { |id| records[id]&.then { |project| Document.for(project).to_result } }
      title_boost(results, query).first(limit)
    end

    def hydrate_devlogs(rows, viewer, limit, query = nil)
      ids = ids_from(rows)
      return [] if ids.empty?

      posts = Post
        .visible_to(viewer)
        .of_devlogs(join: true)
        .where(postable_id: ids, post_devlogs: { deleted_at: nil })
        .includes(:project, :user, :postable)
        .index_by { |post| post.postable_id.to_s }

      results = ids.filter_map { |id| posts[id]&.then { |post| Document.for(post.postable).to_result } }
      title_boost(results, query).first(limit)
    end

    def hydrate_ships(rows, viewer, limit, query = nil)
      ids = ids_from(rows)
      return [] if ids.empty?

      posts = Post
        .visible_to(viewer)
        .of_ship_events(join: true)
        .where(postable_id: ids)
        .where.not(post_ship_events: { certification_status: "rejected" })
        .includes(:project, :user, :postable)
        .index_by { |post| post.postable_id.to_s }

      results = ids.filter_map { |id| posts[id]&.then { |post| Document.for(post.postable).to_result } }
      title_boost(results, query).first(limit)
    end

    def hydrate_users(rows, viewer, limit, query = nil)
      ids = ids_from(rows)
      return [] if ids.empty?

      scope = User.discoverable.where(id: ids).where.not(display_name: [ nil, "" ])
      scope = scope.where(verification_status: "verified") unless viewer&.admin?

      records = scope.index_by { |user| user.id.to_s }
      results = ids.filter_map { |id| records[id]&.then { |user| Document.for(user).to_result } }
      title_boost(results, query).first(limit)
    end

    def title_boost(results, query)
      return results if query.blank?

      q = query.downcase
      results.partition { |r| r[:title].to_s.downcase.include?(q) }.flatten
    end

    def ids_from(rows)
      Array(rows).filter_map { |row| row["record_key"].to_s.split(":", 2).last.presence }
    end

    def cache_key_for(query, viewer, surface, limit)
      visibility_key = viewer&.admin? ? "admin" : "user:#{viewer&.id || 'guest'}"
      "#{CACHE_PREFIX}#{Digest::SHA256.hexdigest([ query, visibility_key, surface, limit ].join(':'))}"
    end

    def read_cache(key)
      return nil unless redis_url.present?

      payload = redis.get(key)
      JSON.parse(payload) if payload.present?
    rescue Redis::BaseError, JSON::ParserError
      nil
    end

    def write_cache(key, results)
      return unless redis_url.present? && result_cache_ttl.positive?

      redis.set(key, results.to_json, ex: result_cache_ttl)
    rescue Redis::BaseError
      nil
    end
  end
end
