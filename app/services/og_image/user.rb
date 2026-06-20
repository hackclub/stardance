module OgImage
  class MockUser
    def initialize(display_name:, bio: nil)
      @display_name = display_name
      @bio = bio
      @created_at = 3.months.ago
    end

    attr_reader :display_name, :bio, :created_at

    def avatar
      MockAvatar.new
    end
  end

  class MockAvatar
    def attached?
      true
    end

    def download
      require "open-uri"
      URI.open("https://placecats.com/400/400").read
    rescue StandardError
      Vips::Image.black(400, 400).draw_rect([ 232, 213, 183 ], 0, 0, 400, 400, fill: true).pngsave_buffer
    end
  end

  class User < Base
    PREVIEWS = {
      "default" => -> { new(sample_user, stats: { projects_count: 5, ships_count: 2, devlogs_count: 12 }) },
      "new_user" => -> { new(sample_user(display_name: "New Member"), stats: { projects_count: 0, ships_count: 0, devlogs_count: 0 }) },
      "with_bio" => -> { new(sample_user(display_name: "hackclub_dev", bio: "Building cool stuff with LEDs and microcontrollers"), stats: { projects_count: 3, ships_count: 1, devlogs_count: 8 }) },
      "long_name" => -> { new(sample_user(display_name: "superlongusername123"), stats: { projects_count: 42, ships_count: 10, devlogs_count: 200 }) }
    }.freeze

    PREVIEW_META = {
      "default" => {
        title: "@hackclub_dev | Stardance",
        description: "5 projects · 2 ships · 12 devlogs",
        url: "https://stardance.hackclub.com/users/hackclub_dev",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      },
      "new_user" => {
        title: "@New Member | Stardance",
        description: "0 projects · 0 ships · 0 devlogs",
        url: "https://stardance.hackclub.com/users/new_member",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      },
      "with_bio" => {
        title: "@hackclub_dev | Stardance",
        description: "Building cool stuff with LEDs and microcontrollers",
        url: "https://stardance.hackclub.com/users/hackclub_dev",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      },
      "long_name" => {
        title: "@superlongusername123 | Stardance",
        description: "42 projects · 10 ships · 200 devlogs",
        url: "https://stardance.hackclub.com/users/superlongusername123",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      }
    }.freeze

    class << self
      def sample_user(display_name: "hackclub_dev", bio: nil)
        MockUser.new(display_name: display_name, bio: bio)
      end
    end

    def initialize(user, stats: {})
      super()
      @user = user
      @stats = stats
    end

    def render
      create_stardance_canvas
      draw_diagonal_scrim(opacity: 0.3)

      draw_avatar
      place_stardance_logo(x: 80, y: 60, width: 240, height: 68)
      draw_title
      draw_stats
      place_star_character(x: 30, y: 20, width: 140, height: 140, gravity: "SouthWest")
    end

    private

    def draw_title
      lines_drawn = draw_glowing_multiline_text(
        "@#{@user.display_name}",
        x: 80,
        y: 170,
        size: 72,
        color: "#fffcf4",
        glow_color: "#ebb7ff",
        max_chars: 18,
        max_lines: 2,
        glow_radius: 6,
        glow_opacity: 0.3,
        font: heading_font_name
      )
      @title_end_y = 170 + (lines_drawn * 72 * 1.3).to_i
    end

    def draw_stats
      stats = build_stats
      return if stats.empty?

      start_y = @title_end_y + 20
      stats.each_with_index do |stat, index|
        icon_x = 80
        icon_y = start_y + (index * 52)
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
          y: icon_y,
          size: 42,
          color: "#c9c9c9"
        )
      end
    end

    def draw_avatar
      place_image(
        @user.avatar,
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
      p = @stats[:projects_count] || 0
      s = @stats[:ships_count] || 0
      d = @stats[:devlogs_count] || 0

      stats = []
      stats << { text: "#{p} #{"project".pluralize(p)}", icon: "rocket.png" }
      stats << { text: "#{s} #{"ship".pluralize(s)}", icon: "box.png" }
      stats << { text: "#{d} #{"devlog".pluralize(d)}", icon: "paper.png" }
      stats
    end
  end
end
