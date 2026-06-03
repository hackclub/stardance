# frozen_string_literal: true

Rails.application.config.x.gorse = ActiveSupport::OrderedOptions.new

credentials = Rails.application.credentials
gorse_credentials = credentials.respond_to?(:dig) ? credentials.dig(:gorse) : nil

Rails.application.config.x.gorse.enabled =
  if gorse_credentials&.key?(:enabled)
    ActiveModel::Type::Boolean.new.cast(gorse_credentials[:enabled])
  else
    ActiveModel::Type::Boolean.new.cast(ENV["GORSE_ENABLED"])
  end

Rails.application.config.x.gorse.endpoint =
  gorse_credentials&.dig(:endpoint).presence || ENV["GORSE_ENDPOINT"].presence

Rails.application.config.x.gorse.api_key =
  gorse_credentials&.dig(:api_key).presence || ENV["GORSE_API_KEY"].presence

Rails.application.config.x.gorse.timeout_seconds =
  (gorse_credentials&.dig(:timeout_seconds).presence || ENV["GORSE_TIMEOUT_SECONDS"].presence || 5).to_f
