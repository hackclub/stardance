module OgImage
  class MockCertificate
    def initialize(name:, hours_at_issue: 42, code: "C5A8G9")
      @name = name
      @hours_at_issue = hours_at_issue
      @code = code
      @created_at = 2.weeks.ago
    end

    attr_reader :name, :hours_at_issue, :code, :created_at
  end

  # Social-card companion to Certificate::Image (the A4 PDF art): same visual
  # language, recomposed for the 1200×630 OG canvas so nothing gets cropped.
  class Certificate < Base
    BACKGROUND_COLOR = "#08061e"
    CARD_COLOR = "#120b26"
    BORDER_COLOR = "#81ffff"
    NAME_COLOR = "#fff8d5"
    GLOW_COLOR = "#ebb7ff"
    BODY_COLOR = "#fffcf4"
    MUTED_COLOR = "#95dbff"

    PREVIEWS = {
      "default" => -> { new(MockCertificate.new(name: "Orpheus Star")) },
      "long_name" => -> { new(MockCertificate.new(name: "Bartholomew Featherstonehaugh III", hours_at_issue: 128)) }
    }.freeze

    PREVIEW_META = {
      "default" => {
        title: "Orpheus Star's Stardance Certificate",
        description: "42 approved hours building and shipping projects on Stardance, Hack Club's Summer 2026 challenge.",
        url: "https://stardance.hackclub.com/certificate?code=C5A8G9",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      },
      "long_name" => {
        title: "Bartholomew Featherstonehaugh III's Stardance Certificate",
        description: "128 approved hours building and shipping projects on Stardance, Hack Club's Summer 2026 challenge.",
        url: "https://stardance.hackclub.com/certificate?code=C5A8G9",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      }
    }.freeze

    def initialize(certificate)
      super()
      @certificate = certificate
    end

    def render
      create_certificate_canvas

      place_stardance_logo(x: 0, y: 40, width: 260, height: 64, gravity: "North")

      draw_text("CERTIFICATE OF ACHIEVEMENT", x: 0, y: 124, size: 28, color: MUTED_COLOR, gravity: "North")

      draw_glowing_text(@certificate.name, x: 0, y: 172, size: name_size, color: NAME_COLOR,
                        glow_color: GLOW_COLOR, glow_radius: 10, gravity: "North", font: title_font_name)

      draw_text("logged #{hours} approved hours building and shipping projects", x: 0, y: 300, size: 27, color: BODY_COLOR, gravity: "North")
      draw_text("on Stardance, Hack Club's Summer 2026 challenge", x: 0, y: 342, size: 27, color: BODY_COLOR, gravity: "North")

      draw_text("Issued #{@certificate.created_at.strftime("%B %-d, %Y")}", x: 0, y: 400, size: 22, color: MUTED_COLOR, gravity: "North")

      draw_code_box

      place_star_character(x: 40, y: 40, width: 120, height: 120, gravity: "SouthEast")
    end

    private

    def hours
      @certificate.hours_at_issue.floor
    end

    def name_size
      case @certificate.name.length
      when 0..18 then 76
      when 19..28 then 58
      else 44
      end
    end

    def create_certificate_canvas
      @image = solid_rgba(WIDTH, HEIGHT, *hex_to_rgb(BACKGROUND_COLOR))

      nebula_path = Rails.root.join("app", "assets", "images", "landing", "how-this-works", "nebula-bg.png").to_s
      if File.exist?(nebula_path)
        place_image(nebula_path, x: 0, y: 0, width: WIDTH, height: HEIGHT, cover: true)
        scrim = solid_rgba(WIDTH, HEIGHT, *hex_to_rgb(BACKGROUND_COLOR), (0.75 * 255).round)
        @image = image.composite(scrim, :over, x: [ 0 ], y: [ 0 ])
      end

      inset = 26
      draw_rounded_rect(x: inset, y: inset, width: WIDTH - inset * 2, height: HEIGHT - inset * 2,
                        radius: 30, fill: BORDER_COLOR)
      draw_rounded_rect(x: inset + 3, y: inset + 3, width: WIDTH - (inset + 3) * 2, height: HEIGHT - (inset + 3) * 2,
                        radius: 27, fill: CARD_COLOR, fill_opacity: 0.96)
    end

    def draw_code_box
      box_width = 470
      box_height = 104
      box_y = HEIGHT - 66 - box_height

      draw_rounded_rect(x: (WIDTH - box_width) / 2, y: box_y, width: box_width, height: box_height,
                        radius: 18, fill: BACKGROUND_COLOR, fill_opacity: 0.85)
      draw_glowing_text(@certificate.code.chars.join(" "), x: 0, y: box_y + 14, size: 42, color: BORDER_COLOR,
                        glow_color: BORDER_COLOR, glow_radius: 8, glow_opacity: 0.4, gravity: "North", font: heading_font_name)
      draw_text("Verify at stardance.hackclub.com/certificate", x: 0, y: box_y + 70, size: 19, color: MUTED_COLOR, gravity: "North")
    end
  end
end
