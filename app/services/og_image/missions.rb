module OgImage
  class Missions < Base
    PREVIEWS = {
      "default" => -> { new(sample_mission) },
      "with_description" => -> { new(sample_mission(description: "Build a collection of micro-games inspired by WarioWare. Each game should last 5 seconds or less and chain together into a frantic sequence.")) },
      "long_name" => -> { new(sample_mission(name: "Build Your Own Programming Language From Scratch")) }
    }.freeze

    STREAK_PATH = Rails.root.join("app", "assets", "images", "landing", "done-before", "star-bg.png").to_s

    class << self
      def sample_mission(name: "Wario-Ware Clone", description: nil, banner: nil, icon: nil)
        OpenStruct.new(
          name: name,
          description: description || "Create a fast-paced collection of micro-games that chain together.",
          banner: banner,
          icon: icon
        )
      end
    end

    def initialize(mission)
      @mission = mission
      super()
    end

    def render
      if @mission.banner&.attached?
        download_attachment(@mission.banner) || render_designed
      else
        render_designed
      end
    end

    private

    def render_designed
      create_stardance_canvas
      place_image(STREAK_PATH, x: -50, y: -40, width: 700, height: 400, cover: false) if File.exist?(STREAK_PATH)
      draw_diagonal_scrim(opacity: 0.85)
      place_stardance_logo(x: 70, y: 55, width: 240, height: 68)
      place_icon_or_star
      draw_mission_label
      draw_mission_name
      draw_description
    end

    def place_icon_or_star
      if @mission.respond_to?(:icon) && @mission.icon.respond_to?(:attached?) && @mission.icon.attached?
        place_image(@mission.icon, x: 80, y: 80, width: 300, height: 300, gravity: "NorthEast", rounded: true, radius: 24)
      else
        place_star_character(x: 80, y: 100, width: 260, height: 260, gravity: "NorthEast")
      end
    end

    def draw_mission_label
      draw_soft_shadow("MISSION", x: 70, y: 170, size: 24, radius: 4, opacity: 0.7)
      draw_text("MISSION", x: 70, y: 170, size: 24, color: "#95dbff")
    end

    def draw_mission_name
      lines = wrap_text(@mission.name, 20).take(3)
      spacing = (64 * 1.3).to_i
      lines.each_with_index do |line, i|
        draw_soft_shadow(line, x: 70, y: 210 + (i * spacing), size: 64, font: heading_font_name, radius: 8, opacity: 0.7)
      end

      @name_lines = draw_glowing_multiline_text(
        @mission.name,
        x: 70, y: 210, size: 64,
        color: "#fffcf4", glow_color: "#ebb7ff",
        max_chars: 20, max_lines: 3,
        glow_radius: 8, glow_opacity: 0.35,
        font: heading_font_name
      )
    end

    def draw_description
      desc = @mission.respond_to?(:description) ? @mission.description : nil
      return unless desc.present?

      start_y = 210 + (@name_lines * 64 * 1.3).to_i + 15
      lines = wrap_text(desc, 42).take(2)
      lines.each_with_index do |line, i|
        draw_soft_shadow(line, x: 70, y: start_y + (i * (28 * 1.3).to_i), size: 28, radius: 4, opacity: 0.5)
      end
      draw_multiline_text(desc, x: 70, y: start_y, size: 28, color: "#c9c9c9", max_chars: 42, max_lines: 2, line_height: 1.3)
    end

    def download_attachment(attachment)
      data = attachment.download
      @image = Vips::Image.new_from_buffer(data, "")
      @image = resize_image(@image, WIDTH, HEIGHT, cover: true)
      @image
    rescue StandardError => e
      Rails.logger.warn("OgImage::Missions: Failed to use banner: #{e.message}")
      nil
    end
  end
end
