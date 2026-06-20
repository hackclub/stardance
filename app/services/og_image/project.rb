module OgImage
  class Project < Base
    PREVIEWS = {
      "default" => -> { new(sample_project) },
      "long_title" => -> { new(sample_project(title: "This Is A Really Long Project Title That Should Wrap To Multiple Lines Nicely")) },
      "no_banner" => -> { new(sample_project(banner: false)) },
      "no_devlogs" => -> { new(sample_project(devlogs_count: 0)) }
    }.freeze

    PREVIEW_META = {
      "default" => {
        title: "floob by @hackclub_dev | Stardance",
        description: "A voice-controlled LED matrix that reacts to music beats in real time.",
        url: "https://stardance.hackclub.com/projects/123",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      },
      "long_title" => {
        title: "This Is A Really Long Project Title by @hackclub_dev | Stardance",
        description: "12 devlogs · 42 hours worked",
        url: "https://stardance.hackclub.com/projects/456",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      },
      "no_banner" => {
        title: "floob by @hackclub_dev | Stardance",
        description: "12 devlogs · 42 hours worked",
        url: "https://stardance.hackclub.com/projects/789",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      },
      "no_devlogs" => {
        title: "floob by @hackclub_dev | Stardance",
        description: "A brand new project on Stardance.",
        url: "https://stardance.hackclub.com/projects/101",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      }
    }.freeze

    class << self
      def sample_project(title: "floob", devlogs_count: 12, banner: true, owner: "hackclub_dev", duration_seconds: 151_200)
        OpenStruct.new(
          title: title,
          devlogs_count: devlogs_count,
          duration_seconds: duration_seconds,
          banner: MockAttachment.new(attached: banner),
          memberships: MockMemberships.new(owner_name: owner)
        )
      end
    end

    def initialize(project)
      super()
      @project = project
    end

    def render
      create_stardance_canvas
      draw_diagonal_scrim(opacity: 0.3)

      draw_thumbnail
      place_stardance_logo(x: 80, y: 60, width: 240, height: 68)
      draw_title
      draw_author
      draw_stats
      place_star_character(x: 30, y: 20, width: 140, height: 140, gravity: "SouthWest")
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

    def draw_author
      owner = @project.memberships.find_by(role: :owner)&.user
      return unless owner

      draw_text(
        "by @#{owner.display_name}",
        x: 80,
        y: @title_end_y + 10,
        size: 38,
        color: "#c9c9c9"
      )
      @author_end_y = @title_end_y + 60
    end

    def draw_stats
      stats = build_stats
      return if stats.empty?

      start_y = (@author_end_y || @title_end_y) + 20
      stats.each_with_index do |stat, index|
        icon_x = 80
        icon_y = start_y + (index * 52)
        text_x = icon_x + 50

        icon_path = Rails.root.join("app", "assets", "images", "icons", stat[:icon])
        place_image(
          icon_path.to_s,
          x: icon_x,
          y: icon_y,
          width: 42,
          height: 42
        )

        draw_text(
          stat[:text],
          x: text_x,
          y: icon_y,
          size: 42,
          color: "#c9c9c9"
        )
      end
    end

    def draw_thumbnail
      image_source = if @project.banner.attached?
        @project.banner
      else
        STAR_CHARACTER_PATH
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

    def build_stats
      stats = []
      stats << { text: "#{@project.devlogs_count} #{"devlog".pluralize(@project.devlogs_count)}", icon: "paper.png" } if @project.devlogs_count.positive?
      stats << { text: "#{hours_logged} #{"hour".pluralize(hours_logged)} worked", icon: "time.png" } if hours_logged > 0
      stats
    end

    def hours_logged
      (@project.duration_seconds.to_i / 3600.0).round
    end
  end
end
