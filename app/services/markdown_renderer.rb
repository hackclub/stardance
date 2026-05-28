class MarkdownRenderer
  ALLOWED_PROTOCOLS = {
    "a"   => { "href" => %w[http https mailto] },
    "img" => { "src"  => %w[http https] }
  }.freeze

  # Bump on any rendered-output change (sanitizer, shortcodes, Rouge, link
  # hardening) — the cache key uses it to invalidate deployment-wide.
  RENDERER_VERSION      = "v2".freeze
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

  def self.render(text)
    return "".freeze if text.blank?

    Rails.cache.fetch([ CACHE_NAMESPACE, RENDERER_VERSION, Digest::SHA1.hexdigest(text) ],
                      expires_in: CACHE_EXPIRES_IN) do
      raw = get_markdown(text)
      sanitised = sanitize_html(raw, extra_tags: %w[u], extra_attributes: %w[target rel])
      doc = Nokogiri::HTML::DocumentFragment.parse(sanitised)
      harden_links_and_images(doc)
      doc.to_html.freeze
    end
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
    Commonmarker.to_html(
      text,
      options: {
        parse: { smart: true },
        extension: {
          strikethrough: true,
          underline: true,
          table: true
        }
      }
    )
  end
end
