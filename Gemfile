source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Annoate for annotating, ig.
  gem "annotaterb"

  # Load .env
  gem "dotenv-rails"

  # Standardized OpenAPI generation
  gem "rspec-rails"
  gem "rswag-specs"
end

# Bullet gem to catch N+1
gem "bullet", group: :development

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Preview email in development [https://github.com/ryanb/letter_opener]
  gem "letter_opener"
  gem "letter_opener_web"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end

gem "pundit", "~> 2.5"
gem "paper_trail"
gem "aasm"
gem "lockbox"
gem "rubocop"
gem "erb_lint"
gem "blind_index"
gem "omniauth"
gem "omniauth-rails_csrf_protection"
gem "omniauth_openid_connect"
gem "omniauth-oauth2"
gem "slack-ruby-client"
gem "blazer"
gem "flipper"
gem "flipper-active_record"
gem "flipper-ui"
gem "flipper-active_support_cache_store"
gem "active_storage_validations"

gem "rails_performance"

gem "commonmarker"
gem "inline_svg"

gem "dartsass-rails", "~> 0.5.1"
gem "slocks"
gem "mission_control-jobs"
gem "view_component"
gem "phlex-rails"
gem "aws-sdk-s3"
gem "faraday"
gem "faraday-retry"

gem "faker", "~> 3.8"
gem "jsbundling-rails", "~> 1.3"
gem "stackprof"
gem "sentry-ruby", "~> 6.4"
gem "sentry-rails", "~> 6.5"

# for pagination
gem "pagy", "~> 43.5"
gem "norairrecord"

gem "awesome_print"
gem "activeinsights"
gem "chartkick"

# Database-level advisory locks for preventing race conditions across processes
gem "with_advisory_lock"

gem "rack-attack"
gem "query_count"

# Rack Mini Profiler gem for performance monitoring
gem "rack-mini-profiler"

gem "redis", "~> 5.4"

gem "ahoy_matey"

gem "countries"
gem "strong_migrations"
gem "skylight"
gem "rbtrace", require: String(ENV.fetch("FEATURE_ENABLE_MEMORY_DUMPS", false)) == "true"

gem "ferret", github: "hackclub/ferret-gem"

gem "neighbor"
