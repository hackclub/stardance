module OgImage
  class Project < Base
    PREVIEWS = {
      "default" => -> { new(sample_project) },
      "long_title" => -> { new(sample_project(title: "This Is A Really Long Project Title That Should Wrap To Multiple Lines Nicely")) },
      "no_banner" => -> { new(sample_project(banner: false)) },
      "no_devlogs" => -> { new(sample_project(devlogs_count: 0)) }
    }.freeze

    class << self
      def sample_project(title: "floob", devlogs_count: 12, banner: true, owner: "hackclub_dev", hours: 42)
        OpenStruct.new(
          title: title,
          devlogs_count: devlogs_count,
          banner: MockAttachment.new(attached: banner),
          memberships: MockMemberships.new(owner_name: owner),
          total_hackatime_hours: hours
        )
      end
    end

    def initialize(project)
      super()
      @project = project
    end

    def render
      create_stardance_canvas

      draw_thumbnail
      place_stardance_logo(x: 80, y: 60, width: 240, height: 68)
      draw_title
      draw_subtitle
    end

    private

    def draw_title
      lines_drawn = draw_glowing_multiline_text(
        @project.title,
        x: 80,
        y: 170,
        size: 72,
        color: "#fffcf4",
        glow_color: "#ebb7ff",
        max_chars: 18,
        max_lines: 3,
        glow_radius: 6,
        glow_opacity: 0.3,
        font: heading_font_name
      )
      @title_end_y = 170 + (lines_drawn * 72 * 1.3).to_i
    end

    def draw_subtitle
      stats = build_stats
      return if stats.empty?

      start_y = @title_end_y + 20
      author = stats.shift

      if author && author[:text]
        draw_text(
          author[:text],
          x: 80,
          y: start_y,
          size: 42,
          color: "#c9c9c9"
        )
      end

      stats_start_y = start_y + 80
      stats.each_with_index do |stat, index|
        icon_x = 80
        icon_y = stats_start_y + (index * 52)
        text_x = icon_x + 50

        if stat[:icon]
          icon_path = Rails.root.join("app", "assets", "images", "icons", stat[:icon])
          place_image(
            icon_path.to_s,
            x: icon_x,
            y: icon_y,
            width: 42,
            height: 42
          )
        end

        draw_text(
          stat[:text],
          x: text_x,
          y: stats_start_y + (index * 52),
          size: 42,
          color: "#c9c9c9"
        )
      end
    end

    def draw_thumbnail
      image_source = if @project.banner.attached?
        @project.banner
      else
        logo_path
      end

      place_image(
        image_source,
        x: 80,
        y: 115,
        width: 400,
        height: 400,
        gravity: "NorthEast",
        rounded: true,
        radius: 24
      )
    end

    def logo_path
      STAR_CHARACTER_PATH
    end

    def build_stats
      stats = []
      owner = @project.memberships.find_by(role: :owner)&.user
      stats << { text: "by @#{owner.display_name}", icon: nil } if owner
      stats << { text: "#{@project.devlogs_count} #{"devlog".pluralize @project.devlogs_count}", icon: "paper.png" } if @project.devlogs_count.positive?
      stats << { text: "#{hours_logged} #{"hour".pluralize hours_logged} worked", icon: "time.png" } if hours_logged > 0
      stats
    end

    def hours_logged
      if @project.respond_to?(:total_hackatime_hours)
        @project.total_hackatime_hours.to_i
      else
        0
      end
    end
  end
end
