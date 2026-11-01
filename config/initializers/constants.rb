Rails.application.config.telescreen_url = (Rails.application.credentials.dig(:constants, :telescreen_url) || ENV["TELESCREEN_URL"]) || "https://telescreen.hackclub.com"
# Direct video file URL (e.g. MP4); blank shows the finale placeholder.
Rails.application.config.stardance_finale_video_url = ENV["STARDANCE_FINALE_VIDEO_URL"].presence
Rails.application.config.stardance_ends_at = Time.find_zone!("America/New_York").local(2026, 10, 31).end_of_day
# The public countdown and finale run later; eligibility cutoffs still use stardance_ends_at.
Rails.application.config.stardance_finale_at = Time.find_zone!("America/New_York").local(2026, 11, 1, 12)
# Ships stay open until the finale, but Hackatime time coded after Stardance
# ends never counts. test_helper.rb clears both so tests keep passing after the dates.
Rails.application.config.stardance_ships_close_at = Rails.application.config.stardance_finale_at
Rails.application.config.stardance_time_logging_ends_at = Rails.application.config.stardance_ends_at
