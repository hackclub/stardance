module OgImage
  class MockAttachment
    def initialize(attached: true)
      @attached = attached
    end

    def attached?
      @attached
    end

    def download
      return nil unless @attached
      placeholder_image
    end

    private

    def placeholder_image
      require "open-uri"
      URI.open("https://cataas.com/cat?width=800&height=600").read
    rescue StandardError
      Vips::Image.black(800, 600).draw_rect([ 232, 213, 183 ], 0, 0, 800, 600, fill: true).pngsave_buffer
    end
  end

  class MockMemberships
    def initialize(owner_name:)
      @owner_name = owner_name
    end

    def find_by(role:)
      return nil unless role == :owner
      OpenStruct.new(user: OpenStruct.new(display_name: @owner_name))
    end
  end

  class Base
    WIDTH = 1200
    HEIGHT = 630

    STARDANCE_LOGO_PATH = Rails.root.join("app", "assets", "images", "landing", "header", "stardance-logo.png").to_s
    STAR_CHARACTER_PATH = Rails.root.join("app", "assets", "images", "landing", "hero", "star-character.png").to_s

    FONT_PATH = Rails.root.join("app", "assets", "fonts", "Exo2.ttf").to_s
    TITLE_FONT_PATH = Rails.root.join("app", "assets", "fonts", "PlayfairDisplay-Italic.ttf").to_s

    attr_reader :image

    def initialize
      @image = nil
    end

    def render
      raise NotImplementedError, "Subclasses must implement #render"
    end

    def to_png
      render
      image.pngsave_buffer
    end

    protected

    def draw_rounded_rect(x:, y:, width:, height:, radius: 24, fill: "#ffffff", fill_opacity: 1.0, stroke: nil, stroke_width: 0)
      r, g, b = hex_to_rgb(fill)
      rect = rounded_rect_mask(width, height, radius)

      if fill_opacity < 1.0
        a = (fill_opacity * 255).round
        overlay = rect * [ r, g, b, a ]
      else
        overlay = rect * [ r, g, b ]
        overlay = overlay.bandjoin(rect * 255) if image.bands == 4
      end

      @image = image.composite(overlay, :over, x: [ x ], y: [ y ])
    end

    def create_patterned_canvas(
      frame_color: "#b0805f",
      card_color: "#7a4b40",
      inset: 26,
      card_radius: 42
    )
      fr, fg, fb = hex_to_rgb(frame_color)
      cr, cg, cb = hex_to_rgb(card_color)

      canvas = solid_rgba(WIDTH, HEIGHT, fr, fg, fb)

      cw = WIDTH - inset * 2
      ch = HEIGHT - inset * 2
      card_mask = rounded_rect_mask(cw, ch, card_radius)
      card = solid_rgba(cw, ch, cr, cg, cb)
      card = card.extract_band(0, n: 3).bandjoin(card_mask)
      canvas = canvas.composite(card, :over, x: [ inset ], y: [ inset ])

      pattern_path = Rails.root.join("app", "assets", "images", "mask", "pattern.png").to_s
      if File.exist?(pattern_path)
        pattern = Vips::Image.new_from_file(pattern_path)
        pattern = pattern.resize(WIDTH.to_f / pattern.width, vscale: HEIGHT.to_f / pattern.height)

        pat_rgb = pattern.extract_band(0, n: 3)
        pat_alpha = pattern.bands >= 4 ? pattern.extract_band(3) : Vips::Image.black(WIDTH, HEIGHT).new_from_image(255).cast(:uchar)

        canvas_rgb = canvas.extract_band(0, n: 3)
        canvas_alpha = canvas.extract_band(3)

        blended = (canvas_rgb * pat_rgb / 255.0).cast(:uchar)
        mix = pat_alpha / 255.0
        inv_mix = mix.linear(-1.0, 1.0)
        canvas_rgb = (blended * mix + canvas_rgb * inv_mix).cast(:uchar)
        canvas = canvas_rgb.bandjoin(canvas_alpha)
      end

      @image = canvas
    end

    def draw_text(text, x:, y:, size: 48, color: "#ffffff", gravity: "NorthWest", font: nil)
      r, g, b = hex_to_rgb(color)
      face = font || font_name
      text_img = Vips::Image.text(text.to_s, font: "#{face} #{size}", fontfile: fontfile_for(face), dpi: 72)
      w, h = text_img.width, text_img.height
      colored = solid_rgba(w, h, r, g, b).extract_band(0, n: 3)
      overlay = colored.bandjoin(text_img).copy(interpretation: :srgb)

      tx, ty = apply_gravity(gravity, x, y, w, h)
      @image = image.composite(overlay, :over, x: [ tx ], y: [ ty ])
    end

    def draw_multiline_text(text, x:, y:, size: 48, color: "#ffffff", line_height: 1, max_chars: 35, max_lines: 3, font: nil)
      lines = wrap_text(text, max_chars).take(max_lines)
      spacing = (size * line_height).to_i

      lines.each_with_index do |line, index|
        draw_text(line, x: x, y: y + (index * spacing), size: size, color: color, font: font)
      end

      lines.size
    end

    def place_image(attachment_or_path, x:, y:, width:, height:, gravity: "NorthWest", rounded: false, radius: 20, cover: true)
      thumb = load_source_image(attachment_or_path, width, height, cover: cover)
      return unless thumb

      if thumb.bands == 3
        full_alpha = Vips::Image.black(thumb.width, thumb.height).new_from_image(255).cast(:uchar)
        thumb = thumb.bandjoin(full_alpha)
      end

      if rounded
        mask = rounded_rect_mask(thumb.width, thumb.height, radius)
        existing_alpha = thumb.extract_band(3)
        thumb = thumb.extract_band(0, n: 3).bandjoin((existing_alpha * mask / 255.0).cast(:uchar))
      end

      thumb = thumb.copy(interpretation: :srgb)
      tx, ty = apply_gravity(gravity, x, y, thumb.width, thumb.height)
      @image = image.composite(thumb, :over, x: [ tx ], y: [ ty ])
    rescue StandardError => e
      Rails.logger.warn("OgImage: Failed to place image: #{e.message}")
    end

    def create_stardance_canvas(
      bg_color: "#08061e",
      card_color: "#120b26",
      inset: 26,
      card_radius: 42
    )
      br, bg, bb = hex_to_rgb(bg_color)
      cr, cg, cb = hex_to_rgb(card_color)

      canvas = solid_rgba(WIDTH, HEIGHT, br, bg, bb)

      cw = WIDTH - inset * 2
      ch = HEIGHT - inset * 2
      card_mask = rounded_rect_mask(cw, ch, card_radius)
      card = solid_rgba(cw, ch, cr, cg, cb)
      card = card.extract_band(0, n: 3).bandjoin(card_mask)
      canvas = canvas.composite(card, :over, x: [ inset ], y: [ inset ])

      nebula_path = Rails.root.join("app", "assets", "images", "landing", "how-this-works", "nebula-bg.png").to_s
      if File.exist?(nebula_path)
        nebula = Vips::Image.new_from_file(nebula_path)
        nebula = nebula.resize(WIDTH.to_f / nebula.width, vscale: HEIGHT.to_f / nebula.height)
        nebula = ensure_four_bands(nebula)
        neb_rgb = nebula.extract_band(0, n: 3)
        neb_alpha = nebula.extract_band(3)
        dimmed_alpha = (neb_alpha * 0.3).cast(:uchar)
        nebula = neb_rgb.bandjoin(dimmed_alpha).copy(interpretation: :srgb)
        canvas = canvas.composite(nebula, :over, x: [ 0 ], y: [ 0 ])
      end

      @image = canvas
    end

    def draw_soft_shadow(text, x:, y:, size: 48, gravity: "NorthWest", font: nil, radius: 6, opacity: 0.6, offset: 2)
      face = font || font_name
      text_img = Vips::Image.text(text.to_s, font: "#{face} #{size}", fontfile: fontfile_for(face), dpi: 72)
      w, h = text_img.width, text_img.height

      pad = radius * 3
      padded_w = w + pad * 2
      padded_h = h + pad * 2
      shadow_base = Vips::Image.black(padded_w, padded_h).cast(:uchar)
      shadow_base = shadow_base.composite(text_img, :over, x: [ pad + offset ], y: [ pad + offset ]).extract_band(0)
      shadow_mask = shadow_base.gaussblur(radius)
      shadow_mask = (shadow_mask * opacity).cast(:uchar)

      shadow_layer = Vips::Image.black(padded_w, padded_h).new_from_image([ 0, 0, 0 ]).cast(:uchar)
      shadow_layer = shadow_layer.bandjoin(shadow_mask).copy(interpretation: :srgb)

      tx, ty = apply_gravity(gravity, x - pad, y - pad, padded_w, padded_h)
      @image = image.composite(shadow_layer, :over, x: [ tx ], y: [ ty ])
    end

    def draw_glowing_text(text, x:, y:, size: 48, color: "#ffffff", glow_color: nil, gravity: "NorthWest", glow_radius: 8, glow_opacity: 0.5, font: nil)
      glow_color ||= color
      gr, gg, gb = hex_to_rgb(glow_color)
      face = font || font_name

      text_img = Vips::Image.text(text.to_s, font: "#{face} #{size}", fontfile: fontfile_for(face), dpi: 72)
      w, h = text_img.width, text_img.height

      pad = glow_radius * 3
      padded_w = w + pad * 2
      padded_h = h + pad * 2
      glow_base = Vips::Image.black(padded_w, padded_h).cast(:uchar)
      glow_base = glow_base.composite(text_img, :over, x: [ pad ], y: [ pad ]).extract_band(0)
      glow_mask = glow_base.gaussblur(glow_radius)
      glow_mask = (glow_mask * glow_opacity).cast(:uchar)

      glow_layer = solid_rgba(padded_w, padded_h, gr, gg, gb).extract_band(0, n: 3)
      glow_layer = glow_layer.bandjoin(glow_mask).copy(interpretation: :srgb)

      tx, ty = apply_gravity(gravity, x - pad, y - pad, padded_w, padded_h)
      @image = image.composite(glow_layer, :over, x: [ tx ], y: [ ty ])

      draw_text(text, x: x, y: y, size: size, color: color, gravity: gravity, font: font)
    end

    def draw_glowing_multiline_text(text, x:, y:, size: 48, color: "#ffffff", glow_color: nil, line_height: 1.3, max_chars: 35, max_lines: 3, glow_radius: 8, glow_opacity: 0.5, font: nil)
      lines = wrap_text(text, max_chars).take(max_lines)
      spacing = (size * line_height).to_i

      lines.each_with_index do |line, index|
        draw_glowing_text(line, x: x, y: y + (index * spacing), size: size, color: color, glow_color: glow_color, glow_radius: glow_radius, glow_opacity: glow_opacity, font: font)
      end

      lines.size
    end

    def font_name
      "Exo 2"
    end

    def heading_font_name
      "Exo 2 Bold"
    end

    def title_font_name
      "Playfair Display Bold Italic"
    end

    def fontfile_for(face)
      if face == title_font_name
        TITLE_FONT_PATH
      else
        FONT_PATH
      end
    end

    def place_stardance_logo(x: 70, y: 60, width: 280, height: 80, gravity: "NorthWest")
      return unless File.exist?(STARDANCE_LOGO_PATH)

      place_image(STARDANCE_LOGO_PATH, x: x, y: y, width: width, height: height, gravity: gravity, cover: false)
    end

    def place_star_character(x: 60, y: 60, width: 220, height: 220, gravity: "SouthEast")
      return unless File.exist?(STAR_CHARACTER_PATH)

      place_image(STAR_CHARACTER_PATH, x: x, y: y, width: width, height: height, gravity: gravity, cover: false)
    end

    def draw_diagonal_scrim(opacity: 0.55)
      r, g, b = hex_to_rgb("#08061e")
      h_ramp = Vips::Image.identity(bands: 1).resize(WIDTH / 256.0, vscale: 1.0)
      h_ramp = h_ramp.linear(-1.0, 255.0).resize(1, vscale: HEIGHT.to_f)

      v_ramp = Vips::Image.identity(bands: 1).resize(1, vscale: HEIGHT / 256.0)
      v_ramp = v_ramp.resize(WIDTH.to_f, vscale: 1.0)

      diag = ((h_ramp + v_ramp) / 2.0 * opacity).cast(:uchar)
      scrim = solid_rgba(WIDTH, HEIGHT, r, g, b).extract_band(0, n: 3).bandjoin(diag).copy(interpretation: :srgb)
      @image = image.composite(scrim, :over, x: [ 0 ], y: [ 0 ])
    end

    private

    def ensure_four_bands(img)
      if img.bands == 3
        full_alpha = Vips::Image.black(img.width, img.height).new_from_image(255).cast(:uchar)
        img.bandjoin(full_alpha)
      elsif img.bands == 1
        rgb = img.bandjoin([ img, img ])
        full_alpha = Vips::Image.black(img.width, img.height).new_from_image(255).cast(:uchar)
        rgb.bandjoin(full_alpha)
      else
        img
      end
    end

    def solid_rgba(w, h, r, g, b, a = 255)
      Vips::Image.new_from_memory(
        ([ r, g, b, a ].pack("C4") * w * h),
        w, h, 4, :uchar
      ).copy(interpretation: :srgb)
    end

    def hex_to_rgb(hex)
      h = hex.to_s.delete("#")
      if h.length == 3
        [ h[0] * 2, h[1] * 2, h[2] * 2 ].map { |v| v.to_i(16) }
      else
        [ h[0, 2], h[2, 2], h[4, 2] ].map { |v| v.to_i(16) }
      end
    end

    def rounded_rect_mask(width, height, radius)
      r = [ radius, width / 2, height / 2 ].min
      quarter = Vips::Image.black(r, r).draw_circle([ 255 ], r, r, r, fill: true).cast(:uchar)
      tl = quarter.extract_area(0, 0, r, r)
      tr = tl.fliphor
      bl = tl.flipver
      br = tl.rot180

      top = tl.join(Vips::Image.black(width - 2 * r, r).new_from_image(255).cast(:uchar), :horizontal).join(tr, :horizontal)
      mid = Vips::Image.black(width, height - 2 * r).new_from_image(255).cast(:uchar)
      bot = bl.join(Vips::Image.black(width - 2 * r, r).new_from_image(255).cast(:uchar), :horizontal).join(br, :horizontal)

      top.join(mid, :vertical).join(bot, :vertical)
    end

    def load_source_image(source, width, height, cover: true)
      img = if source.respond_to?(:download)
        data = source.download
        return nil unless data
        Vips::Image.new_from_buffer(data, "")
      elsif source.is_a?(String) && source.start_with?("http")
        require "open-uri"
        Vips::Image.new_from_buffer(URI(source).open.read, "")
      else
        load_image_file(source)
      end

      resize_image(img, width, height, cover: cover)
    rescue StandardError => e
      Rails.logger.warn("OgImage: Failed to load image: #{e.message}")
      nil
    end

    def load_image_file(path)
      Vips::Image.new_from_file(path, access: :sequential)
    end

    def resize_image(img, width, height, cover: true)
      if cover
        hscale = width.to_f / img.width
        vscale = height.to_f / img.height
        scale = [ hscale, vscale ].max
        img = img.resize(scale, vscale: scale)
        left = (img.width - width) / 2
        top = (img.height - height) / 2
        img.extract_area(left, top, width, height)
      else
        hscale = width.to_f / img.width
        vscale = height.to_f / img.height
        scale = [ hscale, vscale ].min
        img.resize(scale, vscale: scale)
      end
    end

    def apply_gravity(gravity, x, y, obj_width, obj_height)
      case gravity
      when "NorthWest"
        [ x, y ]
      when "NorthEast"
        [ WIDTH - x - obj_width, y ]
      when "SouthWest"
        [ x, HEIGHT - y - obj_height ]
      when "SouthEast"
        [ WIDTH - x - obj_width, HEIGHT - y - obj_height ]
      when "Center"
        [ (WIDTH - obj_width) / 2 + x, (HEIGHT - obj_height) / 2 + y ]
      else
        [ x, y ]
      end
    end

    def wrap_text(text, max_chars)
      words = text.to_s.split
      lines = []
      current_line = ""

      words.each do |word|
        if current_line.empty?
          current_line = word
        elsif (current_line.length + word.length + 1) <= max_chars
          current_line += " #{word}"
        else
          lines << current_line
          current_line = word
        end
      end
      lines << current_line unless current_line.empty?
      lines
    end

    def truncate_text(text, length)
      text.to_s.length > length ? "#{text[0, length - 3]}..." : text.to_s
    end
  end
end
