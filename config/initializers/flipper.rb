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
    Flipper::Adapters::Strict.with_sync_mode do
      %w[
        shop_open
        git_commit_2025-12-25
        voting
        shop_backlogged
        kitchen_comic
        grant_stardust
        voting_locked
        fraud_daily_summary
        shop_order_daily_summary
        shipping
        show_and_tell_live
        missions
        new_onboarding
        gorse_recommendations
        gorse_personalized_feed
        gorse_project_recommendations
        feed_seen_mixer
        week_1_release
        hardware_flow
        hardware_action_items
        hardware_review_undo
        public_hardware_reviews
        ship_event_payouts
        payout_recommendations
        disable_internal_sw_dash_reviews
        sharable_purchase
        no_shigimi_eyes
        devlog_review_pace
        reviewer_progress_panel
        mac_analysis
        sticky_streaks
        public_api_2026-08-28
      ].each { |flag| Flipper.add(flag) }
    end
  rescue StandardError => e
    Rails.logger.warn "Could not initialize flipper: #{e.message}"
  end
end
