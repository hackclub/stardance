require "prawn"

# Wraps the vips-rendered certificate image in a single-page A4-landscape PDF.
# Certificate::Image renders at the A4 aspect ratio, so the image
# fills the page exactly.
class Certificate::Pdf
  def initialize(certificate)
    @certificate = certificate
  end

  def render
    png = StringIO.new(Certificate::Image.new(@certificate).to_png)

    document = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 0)
    document.image png, at: [ 0, document.bounds.height ],
                        width: document.bounds.width,
                        height: document.bounds.height
    document.render
  end
end
