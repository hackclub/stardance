module OgImage
  class Gallery < Base
    MIN_WEEKLY_THRESHOLD = 5
    MIN_TOTAL_THRESHOLD = 10

    PREVIEWS = {
      "default" => -> { new(weekly_count: 42, total_count: 500) },
      "low_weekly" => -> { new(weekly_count: 3, total_count: 150) },
      "low_total" => -> { new(weekly_count: 1, total_count: 5) }
    }.freeze

    PROJECT_IMAGES = %w[yessa.png clement.png alexander.png deltea.png].freeze

    def initialize(weekly_count: 0, total_count: 0)
      super()
      @weekly_count = weekly_count
      @total_count = total_count
    end

    def render
      create_stardance_canvas
      place_project_mosaic
      draw_mosaic_fade
      place_stardance_logo
      draw_tagline
      draw_subtitle
    end

    private

    def place_project_mosaic
      positions = [
        { x: 560, y: 50, w: 310, h: 220 },
        { x: 880, y: 50, w: 310, h: 220 },
        { x: 560, y: 280, w: 310, h: 220 },
        { x: 880, y: 280, w: 310, h: 220 }
      ]

      PROJECT_IMAGES.each_with_index do |file, i|
        path = Rails.root.join("app", "assets", "images", "landing", "projects", file).to_s
        next unless File.exist?(path) && positions[i]

        pos = positions[i]
        place_image(path, x: pos[:x], y: pos[:y], width: pos[:w], height: pos[:h], rounded: true, radius: 16)
      end
    end

    def draw_mosaic_fade
      r, g, b = hex_to_rgb("#08061e")
      grad_w = 600
      ramp = Vips::Image.identity(bands: 1)
      ramp = ramp.resize(grad_w / 256.0, vscale: 1.0)
      ramp = ramp.linear(-1.0, 255.0).cast(:uchar)
      ramp = ramp.resize(1, vscale: HEIGHT.to_f)
      fade = solid_rgba(grad_w, HEIGHT, r, g, b).extract_band(0, n: 3).bandjoin(ramp).copy(interpretation: :srgb)
      @image = image.composite(fade, :over, x: [ 500 ], y: [ 0 ])
    end

    def draw_tagline
      [ "See what teens", "are building." ].each_with_index do |line, i|
        draw_glowing_text(
          line,
          x: 70, y: 200 + (i * 90), size: 68,
          color: "#fffcf4", glow_color: "#ebb7ff",
          glow_radius: 8, glow_opacity: 0.35,
          font: title_font_name
        )
      end
    end

    def draw_subtitle
      subtitle = if @weekly_count >= MIN_WEEKLY_THRESHOLD
        "#{@weekly_count} #{"project".pluralize @weekly_count} built this week"
      elsif @total_count >= MIN_TOTAL_THRESHOLD
        "#{@total_count} #{"project".pluralize @total_count} built so far"
      end
      draw_text(subtitle, x: 70, y: 390, size: 30, color: "#c9c9c9") if subtitle
    end
  end
end
