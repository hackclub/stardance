module OgImage
  class Extensions < Base
    PREVIEWS = {
      "default" => -> { new }
    }.freeze

    def render
      create_stardance_canvas
      place_stardance_logo
      place_star_character
      draw_tagline
      draw_subtitle
    end

    private

    def draw_tagline
      [ "Browser extensions", "from the community." ].each_with_index do |line, i|
        draw_glowing_text(
          line,
          x: 70, y: 220 + (i * 90), size: 72,
          color: "#fffcf4", glow_color: "#ebb7ff",
          glow_radius: 8, glow_opacity: 0.35,
          font: title_font_name
        )
      end
    end

    def draw_subtitle
      draw_text("Tools built by teens, for teens.", x: 70, y: 420, size: 30, color: "#c9c9c9")
    end
  end
end
