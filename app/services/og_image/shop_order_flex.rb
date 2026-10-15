module OgImage
  class MockShopOrder
    MockShopItem = Struct.new(:name, :image)

    def initialize(item_name:, user_name:)
      @shop_item = MockShopItem.new(item_name, MockAttachment.new)
      @user = MockUser.new(display_name: user_name)
    end

    attr_reader :shop_item, :user
  end

  # The "sharable purchase" flex card: a square social image the buyer can
  # copy/download after checkout. Layout mirrors the brand carousel art
  # (Figma "the empty space above", node 5790:29325).
  class ShopOrderFlex < Base
    WIDTH = 1200
    HEIGHT = 1200

    BG_TOP = "#040208"
    BG_BOTTOM = "#160f39"
    TEXT_COLOR = "#fefdfb"
    LINK_COLOR = "#81ffff"

    ART_DIR = Rails.root.join("app", "assets", "images", "og", "sharable-purchase")
    MOON_PATH = ART_DIR.join("moon.png").to_s
    MASCOT_PATH = ART_DIR.join("star-mascot.png").to_s
    FLAG_PATH = ART_DIR.join("hack-club-flag.png").to_s

    PREVIEWS = {
      "default" => -> { new(MockShopOrder.new(item_name: "Hardware Build Fund", user_name: "orpheus")) },
      "short_item" => -> { new(MockShopOrder.new(item_name: "Pile of Stickers", user_name: "orpheus")) },
      "long_item" => -> { new(MockShopOrder.new(item_name: "Bambu Lab A1 Mini 3D Printer Combo", user_name: "superlongusername123")) }
    }.freeze

    PREVIEW_META = {
      "default" => {
        title: "I bought a Hardware Build Fund on Stardance",
        description: "Earned in the Stardance shop",
        url: "https://stardance.hackclub.com/@orpheus",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      },
      "short_item" => {
        title: "I bought a Pile of Stickers on Stardance",
        description: "Earned in the Stardance shop",
        url: "https://stardance.hackclub.com/@orpheus",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      },
      "long_item" => {
        title: "I bought a Bambu Lab A1 Mini 3D Printer Combo on Stardance",
        description: "Earned in the Stardance shop",
        url: "https://stardance.hackclub.com/@superlongusername123",
        site_name: "Stardance - Hack Club",
        twitter_card: "summary_large_image"
      }
    }.freeze

    def initialize(shop_order)
      super()
      @shop_item = shop_order.shop_item
      @user = shop_order.user
    end

    def render
      draw_vertical_gradient(BG_TOP, BG_BOTTOM)
      place_moon
      place_screen_blended(MASCOT_PATH, x: 744, y: 276)
      place_screen_blended(FLAG_PATH, x: 924, y: 294)
      place_stardance_logo(x: 60, y: 60, width: 375, height: 140)
      draw_flex_text
      place_item_art
    end

    private

    def draw_vertical_gradient(top_hex, bottom_hex)
      tr, tg, tb = hex_to_rgb(top_hex)
      br, bg, bb = hex_to_rgb(bottom_hex)

      mix = Vips::Image.xyz(canvas_width, canvas_height).extract_band(1) / (canvas_height - 1).to_f
      rgb = mix.linear([ br - tr, bg - tg, bb - tb ], [ tr, tg, tb ]).cast(:uchar)
      alpha = Vips::Image.black(canvas_width, canvas_height).new_from_image(255).cast(:uchar)
      @image = rgb.bandjoin(alpha).copy(interpretation: :srgb)
    end

    # The moon export carries its own baked-in background, so fade its left
    # edge into the canvas gradient instead of compositing a hard seam.
    def place_moon(fade_width: 190)
      return unless File.exist?(MOON_PATH)

      moon = ensure_four_bands(Vips::Image.new_from_file(MOON_PATH))

      mix = Vips::Image.xyz(moon.width, moon.height).extract_band(0) / fade_width.to_f
      mix = (mix > 1.0).ifthenelse(1.0, mix)
      faded_alpha = (moon.extract_band(3) * mix).cast(:uchar)
      moon = moon.extract_band(0, n: 3).bandjoin(faded_alpha).copy(interpretation: :srgb)

      x = canvas_width - moon.width
      y = canvas_height - moon.height
      @image = image.composite(moon, :over, x: [ x ], y: [ y ])
    rescue StandardError => e
      Rails.logger.warn("OgImage::ShopOrderFlex: failed to place moon: #{e.message}")
    end

    # Mascot/flag exports sit on a dark navy field; screen-blending drops the
    # field into the background while keeping the glow.
    def place_screen_blended(path, x:, y:)
      return unless File.exist?(path)

      overlay = ensure_four_bands(Vips::Image.new_from_file(path)).copy(interpretation: :srgb)
      @image = image.composite(overlay, :screen, x: [ x ], y: [ y ])
    rescue StandardError => e
      Rails.logger.warn("OgImage::ShopOrderFlex: failed to place #{File.basename(path)}: #{e.message}")
    end

    def draw_flex_text
      username = pango_escape("@#{@user.display_name}")
      # Size off the human-visible (pre-escape) length so names with & < > "
      # don't get bumped into a smaller bucket by their escaped expansion.
      truncated_name = truncate_text(@shop_item.name, 28)
      item_name = pango_escape(truncated_name)
      item_size = item_font_size(truncated_name)

      draw_shadowed_text(username, x: 60, y: 316, size: 54)

      draw_shadowed_text("I bought a", x: 60, y: 402, size: 88)
      draw_shadowed_text(item_name, x: 60, y: 506, size: item_size, font: title_font_name)
      third_line_y = 506 + item_size + 24
      draw_shadowed_text("on Stardance", x: 60, y: third_line_y, size: 88)

      profile_url = pango_escape("stardance.hackclub.com/@#{@user.display_name}")
      draw_shadowed_text(profile_url, x: 60, y: third_line_y + 88 + 42, size: 36, color: LINK_COLOR)
    rescue StandardError => e
      Rails.logger.warn("OgImage::ShopOrderFlex: failed to draw text: #{e.message}")
    end

    def draw_shadowed_text(text, x:, y:, size:, color: TEXT_COLOR, font: nil)
      face = font || heading_font_name
      draw_soft_shadow(text, x: x, y: y, size: size, font: face, radius: 10, opacity: 0.5, offset: 4)
      draw_text(text, x: x, y: y, size: size, color: color, font: face)
    end

    def item_font_size(name)
      case name.length
      when 0..14 then 100
      when 15..20 then 80
      else 64
      end
    end

    def place_item_art(box: 360, angle: -5)
      thumb = load_source_image(@shop_item.image, box, box, cover: false)
      return unless thumb

      thumb = ensure_four_bands(thumb)
      rotated = thumb.similarity(angle: angle, background: [ 0, 0, 0, 0 ]).copy(interpretation: :srgb)

      x = canvas_width - 96 - rotated.width
      y = canvas_height - 72 - rotated.height

      shadow_alpha = (rotated.extract_band(3).gaussblur(12) * 0.55).cast(:uchar)
      shadow = Vips::Image.black(rotated.width, rotated.height)
                          .new_from_image([ 0, 0, 0 ])
                          .cast(:uchar)
                          .bandjoin(shadow_alpha)
                          .copy(interpretation: :srgb)
      @image = image.composite(shadow, :over, x: [ x + 8 ], y: [ y + 18 ])
      @image = image.composite(rotated, :over, x: [ x ], y: [ y ])
    rescue StandardError => e
      Rails.logger.warn("OgImage::ShopOrderFlex: failed to place item art: #{e.message}")
    end

    # Vips::Image.text parses Pango markup, so user-provided strings must be
    # escaped or names containing & / < break the render.
    def pango_escape(text)
      CGI.escapeHTML(text.to_s)
    end
  end
end
