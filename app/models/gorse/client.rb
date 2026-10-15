# frozen_string_literal: true

require "cgi"

class Gorse::Client
  def initialize(config: Gorse.config, connection: nil, timeout_seconds: nil)
    @config = config
    @connection = connection
    @timeout_seconds = timeout_seconds || config.timeout_seconds
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

  def delete_user!(user_id) = delete!("api/user/#{CGI.escape(user_id)}")

  def delete_item!(item_id) = delete!("api/item/#{CGI.escape(item_id)}")

  def recommend(user_id, category:, count:)
    response = get("api/recommend/#{CGI.escape(user_id)}", category: category, n: count)
    item_ids(response)
  end

  def non_personalized(name, category:, count:)
    response = get("api/non-personalized/#{CGI.escape(name)}", category: category, n: count)
    item_ids(response)
  end

  private
    attr_reader :config

    def item_ids(response)
      Array(response).map { |item| item.is_a?(Hash) ? item["Id"] : item }.compact
    end

    def get(path, params = {})
      request(:get, path, params)
    end

    def post(path, body)
      request(:post, path, body)
    end

    def put(path, body)
      request(:put, path, body)
    end

    def delete!(path)
      connection.delete(path).body
    rescue Faraday::ResourceNotFound
      nil
    end

    def request(method, path, payload)
      if enabled? && !@failed
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
      @failed = true
      Rails.logger.warn("[Gorse] #{method.to_s.upcase} #{path} failed: #{e.class}: #{e.message}")
      nil
    end

    def connection
      @connection ||= Faraday.new(url: config.endpoint) do |faraday|
        faraday.request :json
        faraday.response :json
        faraday.response :raise_error
        faraday.options.timeout = @timeout_seconds
        faraday.options.open_timeout = @timeout_seconds
        faraday.headers["X-API-Key"] = config.api_key if config.api_key.present?
        faraday.adapter Faraday.default_adapter
      end
    end
end
