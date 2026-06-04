# frozen_string_literal: true

module Gorse
  class Error < StandardError; end

  def self.config = Rails.application.config.x.gorse

  def self.enabled?
    config.enabled && config.endpoint.present? && Flipper.enabled?(:gorse_recommendations)
  end
end
