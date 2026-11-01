Rails.application.config.telescreen_url = (Rails.application.credentials.dig(:constants, :telescreen_url) || ENV["TELESCREEN_URL"]) || "https://telescreen.hackclub.com"
# Direct video file URL (e.g. MP4); blank shows the finale placeholder.
Rails.application.config.stardance_finale_video_url = ENV["STARDANCE_FINALE_VIDEO_URL"].presence
Rails.application.config.stardance_ends_at = Time.find_zone!("America/New_York").local(2026, 10, 31).end_of_day
# Ships stay open until noon ET the day after Stardance ends, but Hackatime time
# coded after it ends never counts. test_helper.rb clears both so tests keep
# passing after the dates.
Rails.application.config.stardance_ships_close_at = Time.find_zone!("America/New_York").local(2026, 11, 1, 12)
Rails.application.config.stardance_time_logging_ends_at = Rails.application.config.stardance_ends_at
