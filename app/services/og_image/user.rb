module OgImage
  class MockUser
    def initialize(display_name:, projects_count:, stardust_earned:, hours_logged:, joined_at: nil)
      @display_name = display_name
      @projects_count = projects_count
      @stardust_earned = stardust_earned
      @hours_logged = hours_logged
      @created_at = joined_at || 3.months.ago
    end

    attr_reader :display_name, :projects_count, :stardust_earned, :hours_logged, :created_at

    def avatar
      MockAvatar.new
    end

    def balance
      @stardust_earned
    end

    def devlog_seconds_total
      @hours_logged * 3600
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
      "default" => -> { new(sample_user) },
      "new_user" => -> { new(sample_user(display_name: "New Member", projects_count: 0, stardust_earned: 0, hours_logged: 0)) },
      "prolific" => -> { new(sample_user(display_name: "Super Builder", projects_count: 50, stardust_earned: 2500, hours_logged: 150)) }
    }.freeze

    class << self
      def sample_user(display_name: "hackclub_dev", projects_count: 5, stardust_earned: 350, hours_logged: 42)
        MockUser.new(
          display_name: display_name,
          projects_count: projects_count,
          stardust_earned: stardust_earned,
          hours_logged: hours_logged
        )
      end
    end

    def initialize(user)
      super()
      @user = user
    end

    def render
      create_stardance_canvas

      draw_avatar
      place_stardance_logo(x: 60, y: 45, width: 200, height: 56)
      draw_title
      draw_subtitle
      place_star_character(x: 30, y: 20, width: 120, height: 120, gravity: "SouthWest")
    end

    private

    def draw_title
      lines_drawn = draw_glowing_multiline_text(
        "@#{@user.display_name}",
        x: 80,
        y: 130,
        size: 82,
        color: "#fffcf4",
        glow_color: "#ebb7ff",
        max_chars: 14,
        max_lines: 2,
        glow_radius: 8,
        glow_opacity: 0.35,
        font: heading_font_name
      )
      @title_end_y = 130 + (lines_drawn * 82 * 1.3).to_i
    end

    def draw_subtitle
      stats = build_stats
      return if stats.empty?

      start_y = @title_end_y + 10
      stats.each_with_index do |stat, index|
        draw_text(
          stat,
          x: 80,
          y: start_y + (index * 44),
          size: 34,
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
      stats = []
      stats << "#{projects_count} #{"project".pluralize projects_count}" if projects_count > 0
      stats << "#{stardust_earned} Stardust earned" if stardust_earned > 0
      stats << "#{hours_logged} #{"hour".pluralize hours_logged} worked" if hours_logged > 0
      stats << "Joined #{joined_ago}"
      stats
    end

    def joined_ago
      return "recently" unless @user.respond_to?(:created_at) && @user.created_at

      ActionController::Base.helpers.time_ago_in_words(@user.created_at) + " ago"
    end

    def projects_count
      return @user.projects.count if @user.respond_to?(:projects)
      return @user.projects_count.to_i if @user.respond_to?(:projects_count)

      0
    end

    def stardust_earned
      if @user.respond_to?(:balance)
        @user.balance.to_i
      elsif @user.respond_to?(:stardust_earned)
        @user.stardust_earned.to_i
      else
        0
      end
    end

    def hours_logged
      if @user.respond_to?(:devlog_seconds_total)
        (@user.devlog_seconds_total / 3600.0).round
      elsif @user.respond_to?(:hours_logged)
        @user.hours_logged.to_i
      else
        0
      end
    end
  end
end
