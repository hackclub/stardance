# frozen_string_literal: true

Rails.application.config.x.sw_ai = ActiveSupport::OrderedOptions.new

credentials = Rails.application.credentials
sw_ai_credentials = credentials.respond_to?(:dig) ? credentials.dig(:sw_ai) : nil

Rails.application.config.x.sw_ai.url =
  sw_ai_credentials&.dig(:url).presence || ENV["SW_AI_URL"].presence || "https://ai.review.hackclub.com"

Rails.application.config.x.sw_ai.api_key =
  sw_ai_credentials&.dig(:api_key).presence || ENV["SW_AI_API_KEY"].presence
