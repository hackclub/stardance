Rails.application.config.telescreen_url = (Rails.application.credentials.dig(:constants, :telescreen_url) || ENV["TELESCREEN_URL"]) || "https://telescreen.hackclub.com"
require Rails.root.join("lib/stardance_finale_media")

# Drop the finished video here and deploy; no environment configuration needed.
finale_media = StardanceFinaleMedia.load(Rails.root.join("public/videos/finale.mp4"))
Rails.application.config.stardance_finale_video_url = finale_media[:url]
Rails.application.config.stardance_finale_video_duration_seconds = finale_media.fetch(:duration, 0.0)
Rails.application.config.stardance_ends_at = Time.find_zone!("America/New_York").local(2026, 10, 31).end_of_day
# The public countdown and finale run later; eligibility cutoffs still use stardance_ends_at.
Rails.application.config.stardance_finale_at = Time.find_zone!("America/New_York").local(2026, 11, 1, 12, 30)
# Ships still close at noon, independently of the later explosion countdown.
# Hackatime time coded after Stardance ends never counts.
# test_helper.rb clears both so tests keep passing after the dates.
Rails.application.config.stardance_ships_close_at = Time.find_zone!("America/New_York").local(2026, 11, 1, 12)
Rails.application.config.stardance_time_logging_ends_at = Rails.application.config.stardance_ends_at
