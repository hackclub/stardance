Rails.application.config.telescreen_url = (Rails.application.credentials.dig(:constants, :telescreen_url) || ENV["TELESCREEN_URL"]) || "https://telescreen.hackclub.com"
# The finale plays from YouTube (https://youtu.be/QDDlOxdq-Ak). Its runtime bounds the
# shared live window, so update both together when swapping the video.
Rails.application.config.stardance_finale_youtube_id = "QDDlOxdq-Ak"
Rails.application.config.stardance_finale_video_duration_seconds = 154.541
Rails.application.config.stardance_ends_at = Time.find_zone!("America/New_York").local(2026, 10, 31).end_of_day
# The public countdown and finale run later; eligibility cutoffs still use stardance_ends_at.
Rails.application.config.stardance_finale_at = Time.find_zone!("America/New_York").local(2026, 11, 1, 12, 35)
# Ships still close at noon, independently of the later explosion countdown.
# Hackatime time coded after Stardance ends never counts.
# test_helper.rb clears both so tests keep passing after the dates.
Rails.application.config.stardance_ships_close_at = Time.find_zone!("America/New_York").local(2026, 11, 1, 12)
Rails.application.config.stardance_time_logging_ends_at = Rails.application.config.stardance_ends_at
