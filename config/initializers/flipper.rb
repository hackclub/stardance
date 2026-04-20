# frozen_string_literal: true

# Flipper is configured automatically with the ActiveRecord adapter
# when flipper-active_record gem is loaded

require "flipper/adapters/active_record"

Rails.application.configure do
  config.flipper.preload = false
  config.flipper.memoize = false
end

# Ensure access flipper feature exists and is enabled globally by default
# This allows all existing users to continue accessing the app
Rails.application.config.after_initialize do
  begin
    # Skip Flipper setup if the tables haven't been created yet (e.g., during migrations)
    next unless ActiveRecord::Base.connection.table_exists?(:flipper_features)

    # Feature flags used throughout the codebase
    Flipper.add(:shop_open) unless Flipper.exist?(:shop_open)
    Flipper.add(:"git_commit_2025-12-25") unless Flipper.exist?(:"git_commit_2025-12-25")
    Flipper.add(:shop_suggestion_box) unless Flipper.exist?(:shop_suggestion_box)
    Flipper.add(:voting) unless Flipper.exist?(:voting)
    Flipper.add(:admin_dark) unless Flipper.exist?(:admin_dark)
    Flipper.add(:shop_backlogged) unless Flipper.exist?(:shop_backlogged)
    Flipper.add(:kitchen_comic) unless Flipper.exist?(:kitchen_comic)
    Flipper.add(:admin_dark_brown_buttons) unless Flipper.exist?(:admin_dark_brown_buttons)
    Flipper.add(:grant_cookies) unless Flipper.exist?(:grant_cookies)
    Flipper.add(:fraud_daily_summary) unless Flipper.exist?(:fraud_daily_summary)
    Flipper.add(:shop_order_daily_summary) unless Flipper.exist?(:shop_order_daily_summary)
    Flipper.add(:shipping) unless Flipper.exist?(:shipping)
    Flipper.add(:show_and_tell_live) unless Flipper.exist?(:show_and_tell_live)
  rescue StandardError => e
    Rails.logger.warn "Could not initialize flipper: #{e.message}"
  end
end
