module OgImage
  class Home < Base
    PREVIEWS = {
      "default" => -> { new }
    }.freeze

    PREVIEW_META = {
      "default" => {
        title: "Stardance - Hack Club",
        description: "The largest STEM event of the summer: make anything you want and earn free prizes.",
        url: "https://stardance.hackclub.com",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      }
    }.freeze

    IMAGE_PATH = Rails.root.join("app", "assets", "images", "landing", "space", "og-default.png").to_s

    def render
      @image = Vips::Image.new_from_file(IMAGE_PATH, access: :sequential)
      @image = @image.resize(WIDTH.to_f / @image.width, vscale: HEIGHT.to_f / @image.height)
    end
  end
end
