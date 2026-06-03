# frozen_string_literal: true

require "cgi"

class Gorse::Client
  def initialize(config: Gorse.config, connection: nil)
    @config = config
    @connection = connection
  end

  def enabled?
    Gorse.enabled?
  end

  def upsert_user(payload)
    post("api/user", payload)
  end

  def upsert_item(payload)
    post("api/item", payload)
  end

  def insert_feedback(payloads)
    put_feedback(payloads)
  end

  def put_feedback(payloads)
    feedback = Array.wrap(payloads).compact
    if feedback.any?
      put("api/feedback", feedback)
    else
      { "RowAffected" => 0 }
    end
  end

  def recommend(user_id, category:, count:)
    response = get("api/recommend/#{CGI.escape(user_id)}", category: category, n: count)
    Array(response).map { |item| item.is_a?(Hash) ? item["Id"] : item }.compact
  end

  private
    attr_reader :config

    def get(path, params = {})
      request(:get, path, params)
    end

    def post(path, body)
      request(:post, path, body)
    end

    def put(path, body)
      request(:put, path, body)
    end

    def request(method, path, payload)
      if enabled?
        response = connection.public_send(method, path) do |request|
          if method == :get
            request.params.update(payload.compact)
          else
            request.body = payload
          end
        end

        response.body
      else
        nil
      end
    rescue Faraday::Error, JSON::ParserError => e
      Rails.logger.warn("[Gorse] #{method.to_s.upcase} #{path} failed: #{e.class}: #{e.message}")
      nil
    end

    def connection
      @connection ||= Faraday.new(url: config.endpoint) do |faraday|
        faraday.request :json
        faraday.response :json
        faraday.response :raise_error
        faraday.options.timeout = config.timeout_seconds
        faraday.options.open_timeout = config.timeout_seconds
        faraday.headers["X-API-Key"] = config.api_key if config.api_key.present?
        faraday.adapter Faraday.default_adapter
      end
    end
end
