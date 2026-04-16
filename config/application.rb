require_relative "boot"

require "rails/all"

# Patch for phlex-rails 2.3.1 compatibility with Rails 8.1+
# Pre-define Phlex::Rails::Streaming with ActiveSupport::Concern BEFORE phlex-rails loads
# See: https://github.com/phlex-ruby/phlex-rails/issues/323
module Phlex
  module Rails
    module Streaming
      extend ActiveSupport::Concern
      include ActionController::Live
    end
  end
end

require_relative "../lib/middleware/serve_avif"
require_relative "../lib/middleware/no_cache_errors"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Battlemage
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks middleware])

    # Autoload secrets submodule models if present
    secrets_models = Rails.root.join("secrets", "app", "models")
    config.autoload_paths << secrets_models if secrets_models.exist?

    # Add secrets assets to asset pipeline
    secrets_images = Rails.root.join("secrets", "assets", "images")
    config.assets.paths << secrets_images if secrets_images.exist?

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    config.eager_load_paths << Rails.root.join("app/mailboxes")

    # MissionControl::Jobs.base_controller_class = "Admin::ApplicationController"
    config.mission_control.jobs.http_basic_auth_enabled = false

    ActiveSupport::Notifications.subscribe("cache_read.active_support") do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      if event.payload[:hit]
        Thread.current[:cache_hits] ||=0
        Thread.current[:cache_hits] += 1
      else
        Thread.current[:cache_misses] ||= 0
        Thread.current[:cache_misses] += 1
      end
    rescue
      Rails.logger.warn("Unable to register cache hit")
    end

    ActiveSupport::Notifications.subscribe("cache_fetch_hit.active_support") do |*args|
      Thread.current[:cache_hits] += 1
    end

    # what do we want? sessions! when do we want em? now!
    config.session_store :cookie_store,
                         key: "_stardance_session_v2",
                         expire_after: 2.months,
                         secure: Rails.env.production?,
                         httponly: true

    config.middleware.insert_before ActionDispatch::Static, ServeAvif
    config.middleware.insert_before ActionDispatch::Static, NoCacheErrors
  end
end
