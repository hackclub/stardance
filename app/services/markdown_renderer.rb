class MarkdownRenderer
  ALLOWED_PROTOCOLS = {
    "a"   => { "href" => %w[http https mailto] },
    "img" => { "src"  => %w[http https] }
  }.freeze

  # Bump on any rendered-output change (sanitizer, shortcodes, Rouge, link
  # hardening) — the cache key uses it to invalidate deployment-wide.
  RENDERER_VERSION      = "v7".freeze
  CACHE_NAMESPACE       = "markdown".freeze
  GUIDE_CACHE_NAMESPACE = "guide-markdown".freeze
  CACHE_EXPIRES_IN      = 7.days

  MENTION_PATTERN = /(?<=\A|[\s(])@([a-zA-Z0-9_-]+)/

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

    Rails.cache.fetch([ CACHE_NAMESPACE, RENDERER_VERSION, "images-#{allow_images}", SlackEmoteRegistry.cache_key, Digest::SHA1.hexdigest(text) ],
                      expires_in: CACHE_EXPIRES_IN) do
      raw = get_markdown(text)
      doc = Nokogiri::HTML::DocumentFragment.parse(raw)
      highlight_code_blocks(doc)
      sanitised = sanitize_html(doc.to_html, extra_tags: %w[u], extra_attributes: %w[target rel class])
      doc = Nokogiri::HTML::DocumentFragment.parse(sanitised)
      remove_images(doc) unless allow_images
      render_slack_emotes(doc)
      render_mentions(doc)
      harden_links_and_images(doc)
      doc.to_html.freeze
    end
  end

  def self.remove_images(doc)
    doc.css("img").remove
  end

  def self.highlight_code_blocks(doc)
    doc.css("pre[lang]").each do |pre|
      lang = pre["lang"]
      lexer = Rouge::Lexer.find(lang)&.new || Rouge::Lexers::PlainText.new
      formatter = Rouge::Formatters::HTML.new
      code = pre.at_css("code") || pre
      highlighted = formatter.format(lexer.lex(code.text))
      pre.replace(%(<pre class="guide-code"><code>#{highlighted}</code></pre>))
    end
  end

  def self.harden_links_and_images(doc)
    doc.css("a").each do |link|
      href = link["href"]
      next if href.blank? || href.start_with?("#")
      next if href.start_with?("/@")
      link["target"] = "_blank"
      link["rel"]    = "noopener noreferrer"
    end

    doc.css("img").each do |img|
      img["loading"]        = "lazy"
      img["decoding"]       = "async"
      img["referrerpolicy"] = "no-referrer"
    end
  end

  def self.render_slack_emotes(doc)
    registry = SlackEmoteRegistry.all
    return if registry.blank?

    doc.traverse do |node|
      next unless node.text?
      next if node.ancestors.any? { |ancestor| %w[code pre kbd samp script style].include?(ancestor.name) }
      next unless node.text.match?(SlackEmoteRegistry::SHORTCODE_PATTERN)

      html = ERB::Util.html_escape(node.text).gsub(SlackEmoteRegistry::SHORTCODE_PATTERN) do
        shortcode = Regexp.last_match(1)
        src = registry[shortcode]
        next Regexp.last_match(0) unless src.present?

        escaped_shortcode = ERB::Util.html_escape(":#{shortcode}:")
        escaped_src = ERB::Util.html_escape(src)
        %(<img src="#{escaped_src}" alt="#{escaped_shortcode}" title="#{escaped_shortcode}" class="slack-emote">)
      end

      node.replace(Nokogiri::HTML::DocumentFragment.parse(html))
    end
  end

  def self.render_mentions(doc)
    doc.traverse do |node|
      next unless node.text?
      next if node.ancestors.any? { |ancestor| %w[code pre kbd samp script style a].include?(ancestor.name) }
      next unless node.text.match?(MENTION_PATTERN)

      html = ERB::Util.html_escape(node.text).gsub(MENTION_PATTERN) do
        username = Regexp.last_match(1)
        escaped = ERB::Util.html_escape(username)
        %(<a href="/@#{escaped}" class="mention">@#{escaped}</a>)
      end

      node.replace(Nokogiri::HTML::DocumentFragment.parse(html))
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
          table: true,
          tasklist: true
        }
      }
    )
  end
end
