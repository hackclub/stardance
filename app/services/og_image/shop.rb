module OgImage
  class Shop < Base
    PREVIEWS = {
      "default" => -> { new }
    }.freeze

    PRIZE_ITEMS = [
      { file: "switch.png", x: 720, y: 50, w: 380, h: 220 },
      { file: "bambu-a1m.png", x: 920, y: 260, w: 240, h: 280 },
      { file: "airpods.png", x: 700, y: 370, w: 200, h: 200 },
      { file: "camera.png", x: 470, y: 60, w: 230, h: 210 },
      { file: "mouse.png", x: 460, y: 380, w: 200, h: 160 }
    ].freeze

    def render
      create_stardance_canvas
      place_prizes
      draw_glow_accent
      place_stardance_logo
      draw_tagline
      draw_subtitle
    end

    private

    def place_prizes
      PRIZE_ITEMS.each do |item|
        path = Rails.root.join("app", "assets", "images", "landing", "prizes", item[:file]).to_s
        next unless File.exist?(path)

        place_image(path, x: item[:x], y: item[:y], width: item[:w], height: item[:h], cover: false)
      end
    end

    def draw_glow_accent
      r, g, b = hex_to_rgb("#ebb7ff")
      glow_w, glow_h = 500, 400
      glow = Vips::Image.black(glow_w, glow_h).new_from_image(255).cast(:uchar)
      glow = glow.gaussblur(80)
      glow = (glow * 0.18).cast(:uchar)
      glow_rgb = solid_rgba(glow_w, glow_h, r, g, b).extract_band(0, n: 3)
      glow_overlay = glow_rgb.bandjoin(glow).copy(interpretation: :srgb)
      @image = image.composite(glow_overlay, :over, x: [ 350 ], y: [ 100 ])
    end

    def draw_tagline
      draw_glowing_text(
        "Earn prizes.",
        x: 70, y: 200, size: 86,
        color: "#fffcf4", glow_color: "#ebb7ff",
        glow_radius: 10, glow_opacity: 0.35,
        font: title_font_name
      )
    end

    def draw_subtitle
      draw_text("Build projects, spend stardust, get real stuff.", x: 70, y: 310, size: 30, color: "#c9c9c9")
    end
  end
end
