# frozen_string_literal: true

# Normalizes a project's build recordings for the certification review pages.
#
# Two capture tools feed the same reviewer-facing gallery — Lapse (current) and
# Lookout (historical, see LookoutService) — and they return differently shaped
# hashes. Which tool captured a clip doesn't matter to a reviewer, so #build
# flattens both into one item shape and orders them newest-first.
#
# #by_devlog then buckets those items into the devlog each one belongs to, so the
# YSWS review page can show a devlog's timelapses next to the media it shipped
# with rather than only in the project-wide gallery at the top of the page.
module Certification
  class RecordingList
    # One row of the gallery:
    #   source:      capture tool, overlaid on the thumbnail ("Lapse"/"Lookout")
    #   video_url:   playable URL, blank while the clip is still being processed
    #   poster_url:  thumbnail, may be blank
    #   name:        reviewer-facing label
    #   duration:    seconds
    #   recorded_at: Time, or nil when the source gave no timestamp
    #   processing:  what to show in place of the player when video_url is blank
    class << self
      # timelapses: Lapse API hashes (LapseService)
      # recordings: Lookout hashes (LookoutService)
      def build(timelapses:, recordings:)
        items = Array(timelapses).map { |tl| from_lapse(tl) } +
                Array(recordings).map { |rec| from_lookout(rec) }

        items.sort_by { |item| item[:recorded_at] || Time.zone.at(0) }.reverse
      end

      # items:   #build output
      # windows: { post_devlog_id => Range of Time } — see
      #          Admin::Certification::YswsController#devlog_time_windows
      #
      # Returns { post_devlog_id => [item, ...] }, newest-first within each
      # devlog. Items with no recorded_at, or falling outside every window, are
      # left out on purpose: they're still listed in the project-wide gallery,
      # and guessing a devlog for them would misattribute build time.
      def by_devlog(items:, windows:)
        dated = Array(items).select { |item| item[:recorded_at].present? }

        windows.transform_values do |window|
          dated.select { |item| window.cover?(item[:recorded_at]) }
        end
      end

      private

      def from_lapse(timelapse)
        {
          source: "Lapse",
          video_url: timelapse[:playbackUrl],
          poster_url: timelapse[:thumbnailUrl],
          name: timelapse[:name].presence || "Untitled recording",
          duration: timelapse[:duration],
          recorded_at: lapse_recorded_at(timelapse[:createdAt]),
          processing: timelapse[:visibility] == "FAILED_PROCESSING" ? "Processing failed" : "Still processing…"
        }
      end

      def from_lookout(recording)
        {
          source: "Lookout",
          video_url: recording[:video_url],
          poster_url: recording[:thumbnail_url],
          name: recording[:mode].present? ? "#{recording[:mode].capitalize} recording" : "Screen recording",
          duration: recording[:duration],
          recorded_at: recording[:recorded_at],
          processing: "Still processing…"
        }
      end

      # Lapse reports creation time in epoch milliseconds.
      def lapse_recorded_at(created_at)
        return nil if created_at.blank?

        Time.zone.at(created_at.to_i / 1000)
      end
    end
  end
end
