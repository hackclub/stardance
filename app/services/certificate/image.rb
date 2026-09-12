require "rqrcode_core"

# Renders the certificate art from the Figma design ("the empty space above",
# node 7084-46). Layout coordinates are in Figma design units (842×595, A4
# landscape) scaled by SCALE, so the PDF fills the page edge to edge at print
# resolution. Static pieces (background collage, title, signature, sponsor
# logos) are baked 4x Figma exports under app/assets/images/certificate/;
# the recipient name, body copy, verify code, and QR are drawn live.
class Certificate::Image < OgImage::Base
  SCALE = 4 # 842×595 design units × 4 = 3368×2380, ~290 DPI on A4
  WIDTH = 842 * SCALE
  HEIGHT = 595 * SCALE

  BACKGROUND_COLOR = "#08061e"
  FRAME_COLOR = "#f4ebb9"
  # Vanity domain; redirects to stardance.hackclub.com.
  VERIFY_HOST = "stardance.space"

  ASSET_DIR = Rails.root.join("app", "assets", "images", "certificate")

  def initialize(certificate)
    super()
    @certificate = certificate
  end

  def render
    @image = solid_rgba(WIDTH, HEIGHT, *hex_to_rgb(BACKGROUND_COLOR))

    draw_frame
    place_asset("logo-lockup.png", x: 48, y: 48)
    place_asset("title-lockup.png", x: 314.5, y: 48)
    place_asset("signature.png", x: 351, y: 360)
    #  scale 0.77 sx 274 sy 459
    #  sponsor-logos.png was here
    place_asset("sponsor-logos-full.png", x: 274, y: 459, scale: 0.77)

    draw_qr_block
    draw_recipient
    draw_body
  end

  private

  # Design units → canvas pixels.
  def s(value)
    (value * SCALE).round
  end

  # Triple cream ring plus the background collage clipped inside the
  # innermost ring, matching the Figma frame nesting.
  def draw_frame
    draw_border_ring(x: s(8), y: s(8), width: s(826), height: s(579), radius: s(20), opacity: 0.25)
    draw_border_ring(x: s(16), y: s(16), width: s(810), height: s(563), radius: s(14), opacity: 0.5)
    place_image(ASSET_DIR.join("template-bg.png").to_s,
                x: s(24), y: s(24), width: s(794), height: s(547), rounded: true, radius: s(8))
    draw_border_ring(x: s(24), y: s(24), width: s(794), height: s(547), radius: s(8), opacity: 1.0)
  end

  def place_asset(filename, x:, y:, scale: 1)
    asset = Vips::Image.new_from_file(ASSET_DIR.join(filename).to_s)
    asset = asset.resize(scale) if scale != 1
    @image = image.composite(asset.copy(interpretation: :srgb), :over, x: [ s(x) ], y: [ s(y) ])
  end

  def draw_border_ring(x:, y:, width:, height:, radius:, opacity:, thickness: SCALE * 2, color: FRAME_COLOR)
    outer = rounded_rect_mask(width, height, radius)
    inner = rounded_rect_mask(width - thickness * 2, height - thickness * 2, [ radius - thickness, 2 ].max)
    ring = (outer - inner.embed(thickness, thickness, width, height)).cast(:uchar)
    ring = (ring * opacity).cast(:uchar) if opacity < 1.0

    r, g, b = hex_to_rgb(color)
    overlay = solid_rgba(width, height, r, g, b).extract_band(0, n: 3).bandjoin(ring).copy(interpretation: :srgb)
    @image = image.composite(overlay, :over, x: [ x ], y: [ y ])
  end

  # QR box top-right plus the rotated "to verify this award" caption.
  def draw_qr_block
    draw_border_ring(x: s(695), y: s(48), width: s(56), height: s(56), radius: SCALE,
                     opacity: 0.6, thickness: SCALE, color: "#ffffff")

    qr = qr_image(size: s(48))
    @image = image.composite(qr, :over, x: [ s(695) + (s(56) - qr.width) / 2 ], y: [ s(48) + (s(56) - qr.height) / 2 ])

    caption = markup_text(<<~MARKUP.strip, font: "Exo 2", size: s(10))
      #{muted_span("to verify this award, go to")}
      #{bold_span("#{VERIFY_HOST}/certificate")}
      #{muted_span("and enter code")} #{bold_span(@certificate.code)}
    MARKUP
    @image = image.composite(caption.rot90, :over, x: [ s(757) ], y: [ s(48) ])
  end

  def draw_recipient
    presented = markup_text(muted_span("The following award is presented to"), font: "Exo 2", size: s(12))
    @image = image.composite(presented, :over, x: [ (WIDTH - presented.width) / 2 ], y: [ s(168) ])

    size = s(36)
    name = nil
    loop do
      name = markup_text("<span foreground=\"#FFFFFF\">#{pango_escape(@certificate.name)}</span>",
                         font: "Playfair Display Italic", size: size,
                         fontfile: OgImage::Base::TITLE_FONT_PATH)
      break if name.width <= s(500) || size <= s(20)

      size -= SCALE * 2
    end
    @image = image.composite(name, :over, x: [ (WIDTH - name.width) / 2 ], y: [ s(188) + (s(48) - name.height) / 2 ])
  end

  def draw_body
    hours = @certificate.hours_at_issue.floor
    projects = @certificate.approved_projects_count
    project_phrase = "#{projects} #{"project".pluralize(projects)}"

    markup = "#{muted_span('for their participation in the ')}#{bold_span('Hack Club Stardance Challenge')}#{muted_span(".\n\nFor building and shipping #{project_phrase}, representing #{hours} hours of dedicated work, this certificate recognises their outstanding independent project development and meaningful contribution to Hack Club’s worldwide community of developers.")}"

    body = markup_text(markup, font: "Exo 2", size: s(12), width: s(412), spacing: s(4))
    @image = image.composite(body, :over, x: [ (WIDTH - body.width) / 2 ], y: [ s(246) ])
  end

  def markup_text(markup, font:, size:, fontfile: OgImage::Base::FONT_PATH, width: nil, spacing: nil)
    options = { font: "#{font} #{size}", fontfile: fontfile, dpi: 72, rgba: true }
    options[:width] = width if width
    options[:align] = :centre if width
    options[:spacing] = spacing if spacing
    Vips::Image.text(markup, **options).copy(interpretation: :srgb)
  end

  def muted_span(text)
    "<span foreground=\"#FFFFFF\" alpha=\"60%\">#{pango_escape(text)}</span>"
  end

  def bold_span(text)
    "<span foreground=\"#FFFFFF\" weight=\"bold\">#{pango_escape(text)}</span>"
  end

  # White-on-dark QR encoding the verify URL, drawn in the Figma's
  # rounded-module style: supersample the module grid, blur, and re-threshold
  # so each blob of modules gets rounded corners, then halve for antialiasing.
  def qr_image(size:)
    qr = RQRCodeCore::QRCode.new("https://#{VERIFY_HOST}/certificate?code=#{@certificate.code}", level: :m)
    modules = qr.modules
    count = modules.length

    bytes = modules.flatten.map { |dark| dark ? 255 : 0 }.pack("C*")
    mask = Vips::Image.new_from_memory(bytes, count, count, 1, :uchar)

    supersample = size * 2
    module_px = supersample.to_f / count
    mask = mask.resize(module_px, kernel: :nearest)
    mask = mask.gaussblur(module_px * 0.4) > 127
    mask = mask.resize(0.5)

    solid_rgba(mask.width, mask.height, 255, 255, 255)
      .extract_band(0, n: 3)
      .bandjoin(mask.cast(:uchar))
      .copy(interpretation: :srgb)
  end
end
