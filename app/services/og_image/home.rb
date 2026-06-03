module OgImage
  class Home < Base
    PREVIEWS = {
      "default" => -> { new }
    }.freeze

    IMAGE_PATH = Rails.root.join("app", "assets", "images", "landing", "space", "og-default.png").to_s

    def render
      @image = Vips::Image.new_from_file(IMAGE_PATH, access: :sequential)
      @image = @image.resize(WIDTH.to_f / @image.width, vscale: HEIGHT.to_f / @image.height)
    end
  end
end
