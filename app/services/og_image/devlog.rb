module OgImage
  class Devlog
    PLACEHOLDER_PATH = Rails.root.join("app", "assets", "images", "profile", "default-banner.png").to_s

    PREVIEWS = {
      "default" => -> { new(has_image: true) },
      "no_image" => -> { new(has_image: false) }
    }.freeze

    PREVIEW_META = {
      "default" => {
        title: "@hackclub_dev on LED Matrix | Stardance",
        description: "Just finished wiring up the LED matrix! The colors are finally syncing with the music.",
        url: "https://stardance.hackclub.com/projects/123/devlogs/456",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      },
      "no_image" => {
        title: "@hackclub_dev on Power Supply v2 | Stardance",
        description: "Spent 2 hours debugging a power issue. Turned out the ground wire was loose.",
        url: "https://stardance.hackclub.com/projects/123/devlogs/789",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary"
      }
    }.freeze

    def initialize(has_image: true)
      @has_image = has_image
    end

    def to_png
      if @has_image && File.exist?(PLACEHOLDER_PATH)
        File.read(PLACEHOLDER_PATH, mode: "rb")
      else
        nil
      end
    end
  end
end
