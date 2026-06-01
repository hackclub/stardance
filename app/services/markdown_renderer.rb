class MarkdownRenderer
  ALLOWED_PROTOCOLS = {
    "a"   => { "href" => %w[http https mailto] },
    "img" => { "src"  => %w[http https] }
  }.freeze

  # Bump on any rendered-output change (sanitizer, shortcodes, Rouge, link
  # hardening) — the cache key uses it to invalidate deployment-wide.
  RENDERER_VERSION      = "v5".freeze
  CACHE_NAMESPACE       = "markdown".freeze
  GUIDE_CACHE_NAMESPACE = "guide-markdown".freeze
  CACHE_EXPIRES_IN      = 7.days

  BLANK_GUIDE_RESULT = GuideMarkdownRenderer::Result.new(html: "".freeze, outline: [].freeze).freeze

  def self.sanitize_html(html, extra_tags: [], extra_attributes: [])
    ActionController::Base.helpers.sanitize(
      html,
      tags:       ActionView::Base.sanitized_allowed_tags + extra_tags,
      attributes: ActionView::Base.sanitized_allowed_attributes + extra_attributes,
      protocols:  ALLOWED_PROTOCOLS
    )
  end

  def self.render_guide(text)
    return BLANK_GUIDE_RESULT if text.blank?

    Rails.cache.fetch([ GUIDE_CACHE_NAMESPACE, RENDERER_VERSION, Digest::SHA1.hexdigest(text) ],
                      expires_in: CACHE_EXPIRES_IN) do
      GuideMarkdownRenderer.render(text)
    end
  end

  def self.render(text, allow_images: true)
    return "".freeze if text.blank?

    Rails.cache.fetch([ CACHE_NAMESPACE, RENDERER_VERSION, "images-#{allow_images}", Digest::SHA1.hexdigest(text) ],
                      expires_in: CACHE_EXPIRES_IN) do
      doc = get_markdown(text)
      promote_raw_images(doc)

      raw = doc.to_html
      sanitised = sanitize_html(raw, extra_tags: %w[u], extra_attributes: %w[target rel])
      doc = Nokogiri::HTML::DocumentFragment.parse(sanitised)
      remove_images(doc) unless allow_images
      harden_links_and_images(doc)
      doc.to_html.freeze
    end
  end

  def self.remove_images(doc)
    doc.css("img").remove
  end

  def self.harden_links_and_images(doc)
    doc.css("a").each do |link|
      href = link["href"]
      next if href.blank? || href.start_with?("#")
      link["target"] = "_blank"
      link["rel"]    = "noopener noreferrer"
    end

    doc.css("img").each do |img|
      img["loading"]        = "lazy"
      img["decoding"]       = "async"
      img["referrerpolicy"] = "no-referrer"
    end
  end

  private

  def self.get_markdown(text)
    Commonmarker.parse(
      text,
      options: {
        parse: { smart: true },
        extension: {
          strikethrough: true,
          underline: true,
          table: true,
          tasklist: true
        }
      }
    )
  end

  def self.promote_raw_images(doc)
    nodes = []
    doc.walk do |node|
      nodes << node if node.type == :html_inline || node.type == :html_block
    end

    nodes.each do |node|
      image = raw_image_node(node)
      next if image.blank?

      if node.type == :html_block
        paragraph = Commonmarker::Node.new(:paragraph)
        paragraph.append_child(image)
        node.replace(paragraph)
      else
        node.replace(image)
      end
    end
  end

  def self.raw_image_node(node)
    fragment = Nokogiri::HTML5.fragment(node.to_commonmark)
    children = fragment.children.reject { |child| child.text? && child.text.blank? }
    return unless children.one? && children.first.element? && children.first.name == "img"

    img = children.first

    src = img["src"].presence
    return if src.blank?

    image = Commonmarker::Node.new(:image, url: src)
    image.title = img["title"].presence if img["title"].present?

    alt = img["alt"].to_s
    if alt.present?
      alt_node = Commonmarker::Node.new(:text)
      alt_node.string_content = alt
      image.append_child(alt_node)
    end

    image
  end
end
