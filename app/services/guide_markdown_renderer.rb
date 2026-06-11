class GuideMarkdownRenderer
  Result = Struct.new(:html, :outline, keyword_init: true) do
    def to_s = html.to_s
  end

  class Error < StandardError; end

  MAX_SHORTCODE_PASSES = 200
  MAX_RECURSION_DEPTH  = 4

  BLOCK_SHORTCODE_RE = /^:::(?<name>[a-z][a-z0-9_-]*)(?<attrs>(?:[ \t]+[a-z][a-z0-9_-]*=(?:"[^"\n]*"|[^\s"]+))*)[ \t]*\n(?<content>(?:(?!^:::).)*)^:::[ \t]*(?=\n|\z)/m
  INLINE_SHORTCODE_RE = /::(?<name>[a-z][a-z0-9_-]*)\[(?<content>[^\[\]\n]*)\]/x
  ATTR_RE             = /([a-z][a-z0-9_-]*)=("[^"]*"|\S+)/

  CALLOUT_TYPES     = %w[info tip warning danger].freeze
  BLOCK_SHORTCODES  = %w[callout collapse var].freeze
  INLINE_SHORTCODES = %w[kbd mark var-ref var-slug].freeze

  # Guide variables are client-side only: the renderer emits static inputs and
  # reference spans, and mission_guide_variables_controller.js fills in the
  # reader's value from localStorage — rendered HTML stays cacheable per-content.
  VAR_NAME_RE = /\A[a-z][a-z0-9_-]*\z/

  # Rouge's lexer tags are by convention alphanumeric / underscore / dash, but
  # we filter defensively before interpolating into a class attribute.
  LANGUAGE_CLASS_RE = /\A[a-z0-9_-]+\z/i

  def self.render(text)
    new(text).call
  end

  def initialize(text)
    @text = text.to_s
    @block_registry  = []
    @inline_registry = []
    @code_registry   = []
    # Per-render salt prevents users from typing a literal marker token like
    # `[[GUIDE_BLOCK:0]]` and tricking the expand passes into replaying a
    # registry entry. Markers are emitted by us during extraction and only
    # ever match for the same instance's expansion phase.
    @marker_salt = SecureRandom.hex(8)
  end

  def call
    extracted = extract_blocks(@text)
    text_with_markers = extract_inlines_in_place(extracted)
    @block_registry.each_with_index do |entry, i|
      @block_registry[i] = entry.merge(content: extract_inlines_in_place(entry[:content]))
    end

    outline = build_outline(text_with_markers)
    html    = render_pipeline(text_with_markers, depth: 0).freeze
    Result.new(html: html, outline: outline).freeze
  end

  private

  def extract_blocks(text)
    pass = 0
    loop do
      pass += 1
      raise Error, "too many shortcode passes" if pass > MAX_SHORTCODE_PASSES

      match = text.match(BLOCK_SHORTCODE_RE)
      break text unless match

      name  = match[:name]
      attrs = parse_attrs(match[:attrs])

      unless BLOCK_SHORTCODES.include?(name)
        text = text.sub(match[0], "")
        next
      end

      id = @block_registry.size
      @block_registry << { name: name, attrs: attrs, content: match[:content] }
      text = text.sub(match[0], "\n\n#{block_marker(id)}\n\n")
    end
    text
  end

  def extract_inlines_in_place(text)
    text.gsub(INLINE_SHORTCODE_RE) do
      name    = Regexp.last_match[:name]
      content = Regexp.last_match[:content]
      if INLINE_SHORTCODES.include?(name)
        id = @inline_registry.size
        @inline_registry << { name: name, content: content }
        inline_marker(id)
      else
        ""
      end
    end
  end

  def block_marker_re  = /\[\[GUIDE_BLOCK:#{Regexp.escape(@marker_salt)}:(\d+)\]\]/
  def inline_marker_re = /\[\[GUIDE_INLINE:#{Regexp.escape(@marker_salt)}:(\d+)\]\]/
  def code_marker_re   = /\A\[\[GUIDE_CODE:#{Regexp.escape(@marker_salt)}:(\d+)\]\]\z/

  def block_marker(id)  = "[[GUIDE_BLOCK:#{@marker_salt}:#{id}]]"
  def inline_marker(id) = "[[GUIDE_INLINE:#{@marker_salt}:#{id}]]"
  def code_marker(id)   = "[[GUIDE_CODE:#{@marker_salt}:#{id}]]"

  def parse_attrs(str)
    attrs = {}
    str.to_s.scan(ATTR_RE) do |key, value|
      value = value[1..-2] if value.start_with?('"') && value.end_with?('"')
      attrs[key] = value
    end
    attrs
  end

  def slug_assigner
    seen = Hash.new(0)
    ->(heading_text) {
      base = heading_text.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      base = "section" if base.empty?
      suffix = seen[base].zero? ? "" : "-#{seen[base] + 1}"
      seen[base] += 1
      "section-#{base}#{suffix}"
    }
  end

  def build_outline(text)
    assign = slug_assigner
    outline = []
    text.scan(/^##[ \t]+(.+?)[ \t]*$/) do |(heading_text)|
      cleaned = heading_text.gsub(/[*_`]/, "").strip
      next if cleaned.empty?
      outline << { index: outline.size, text: cleaned, id: assign.call(cleaned) }
    end
    outline.freeze
  end

  def render_pipeline(text, depth:)
    raise Error, "guide markdown recursion too deep" if depth > MAX_RECURSION_DEPTH

    raw_html = Commonmarker.to_html(
      text,
      options: {
        parse: { smart: true },
        extension: {
          strikethrough: true,
          underline: true,
          table: true,
          autolink: true,
          tagfilter: true
        }
      },
    )

    # Pull code blocks out BEFORE sanitize — class="language-X" wouldn't survive.
    raw_html = extract_code_blocks(raw_html)

    sanitized = MarkdownRenderer.sanitize_html(
      raw_html,
      extra_tags:       %w[u kbd mark table thead tbody tfoot tr th td],
      extra_attributes: %w[target rel]
    )

    doc = Nokogiri::HTML5.fragment(sanitized)
    expand_blocks(doc, depth: depth)
    expand_inlines(doc)
    expand_code_blocks(doc)
    section_by_h2(doc) if depth.zero?
    post_process(doc)
    doc.to_html
  end

  def extract_code_blocks(html)
    doc = Nokogiri::HTML5.fragment(html)
    # Replace Commonmarker's inline-styled <pre lang> blocks with a placeholder;
    # we'll re-render via Rouge in expand_code_blocks.
    doc.css("pre[lang]").each do |pre_node|
      language = pre_node["lang"].to_s.strip
      next if language.empty?

      code_text = pre_node.text
      id = @code_registry.size
      @code_registry << { language: language, code: code_text }

      placeholder = Nokogiri::XML::Node.new("pre", doc.document)
      placeholder.content = code_marker(id)
      pre_node.replace(placeholder)
    end
    doc.to_html
  end

  def expand_code_blocks(doc)
    doc.css("pre").each do |pre|
      match = pre.text.strip.match(code_marker_re)
      next unless match

      entry = @code_registry[match[1].to_i]
      next unless entry

      pre.replace(Nokogiri::HTML5.fragment(render_code_block(entry)))
    end
  end

  def render_code_block(entry)
    lexer = Rouge::Lexer.find(entry[:language])&.new || Rouge::Lexers::PlainText.new
    formatter = Rouge::Formatters::HTML.new
    # Inline shortcode extraction runs on the raw markdown, so markers survive
    # inside fenced code. Split on them and highlight the chunks in between.
    highlighted = entry[:code].split(inline_marker_re).map.with_index { |part, i|
      i.odd? ? expand_inline_entry(part.to_i) : formatter.format(lexer.lex(part))
    }.join
    language_class = lexer.tag.to_s
    language_class = "plaintext" unless language_class.match?(LANGUAGE_CLASS_RE)
    %(<pre class="guide-code"><code class="language-#{language_class}">#{highlighted}</code></pre>)
  end

  # Collect-then-apply: mutating during doc.traverse invalidates libxml2's cursor.
  def expand_blocks(doc, depth:)
    block_re = block_marker_re
    sole_block_re = /\A#{block_re.source}\z/
    replacements = []
    doc.traverse do |node|
      next unless node.text?
      next unless node.content =~ block_re

      parent = node.parent
      if parent && parent.name == "p" && parent.content.strip =~ sole_block_re
        id = Regexp.last_match(1).to_i
        entry = @block_registry[id]
        replacement_html = entry ? render_block_shortcode(entry, depth: depth + 1) : ""
        replacements << [ parent, replacement_html ]
      else
        new_content = node.content.gsub(block_re) do
          id = Regexp.last_match(1).to_i
          entry = @block_registry[id]
          entry ? render_block_shortcode(entry, depth: depth + 1) : ""
        end
        replacements << [ node, new_content ]
      end
    end

    replacements.each do |target, html|
      target.replace(Nokogiri::HTML5.fragment(html))
    end
  end

  def expand_inlines(doc)
    inline_re = inline_marker_re
    replacements = []
    doc.traverse do |node|
      next unless node.text?
      next unless node.content =~ inline_re

      new_content = node.content.gsub(inline_re) do
        expand_inline_entry(Regexp.last_match(1).to_i)
      end
      replacements << [ node, new_content ]
    end

    replacements.each do |target, html|
      target.replace(Nokogiri::HTML5.fragment(html))
    end
  end

  def section_by_h2(doc)
    children = doc.children.to_a
    return if children.empty?

    assign = slug_assigner
    sections = []
    current  = []
    section_index = -1

    children.each do |child|
      if child.element? && child.name == "h2"
        sections << { index: section_index, nodes: current } if section_index >= 0 || current.any?
        section_index += 1
        h2_text = child.text.strip
        child["id"] = assign.call(h2_text) if h2_text.present?
        current = [ child ]
      else
        current << child
      end
    end
    sections << { index: section_index, nodes: current } if current.any?

    children.each(&:unlink)

    sections.each do |section|
      if section[:index] < 0
        section[:nodes].each { |n| doc.add_child(n) }
      else
        section_node = Nokogiri::XML::Node.new("section", doc.document)
        section_node["class"] = "guide-section"
        section_node["data-section-index"] = section[:index].to_s
        section[:nodes].each { |n| section_node.add_child(n) }
        doc.add_child(section_node)
      end
    end
  end

  def post_process(doc)
    MarkdownRenderer.harden_links_and_images(doc)
  end

  def render_block_shortcode(entry, depth:)
    case entry[:name]
    when "callout"    then render_callout(entry, depth: depth)
    when "collapse"   then render_collapse(entry, depth: depth)
    when "var"        then render_var(entry)
    else ""
    end
  end

  def expand_inline_entry(id)
    entry = @inline_registry[id]
    entry ? render_inline_shortcode(entry) : ""
  end

  def render_inline_shortcode(entry)
    content = ERB::Util.html_escape(entry[:content].to_s)
    case entry[:name]
    when "kbd"      then %(<kbd class="guide-kbd">#{content}</kbd>)
    when "mark"     then %(<mark class="guide-mark">#{content}</mark>)
    when "var-ref"  then render_var_ref(entry, slugged: false)
    when "var-slug" then render_var_ref(entry, slugged: true)
    else content
    end
  end

  def render_callout(entry, depth:)
    type = entry[:attrs]["type"].to_s
    type = "info" unless CALLOUT_TYPES.include?(type)
    title_attr = entry[:attrs]["title"].to_s
    title_html = title_attr.empty? ? "" : %(<p class="guide-callout__title">#{ERB::Util.html_escape(title_attr)}</p>)
    inner_html = render_pipeline(entry[:content], depth: depth)
    <<~HTML
      <aside class="guide-callout guide-callout--#{type}" role="note">
        #{title_html}
        <div class="guide-callout__body">#{inner_html}</div>
      </aside>
    HTML
  end

  def render_collapse(entry, depth:)
    summary = entry[:attrs]["summary"].to_s
    summary = "Details" if summary.empty?
    summary_html = ERB::Util.html_escape(summary)
    inner_html = render_pipeline(entry[:content], depth: depth)
    <<~HTML
      <details class="guide-collapse">
        <summary class="guide-collapse__summary">#{summary_html}</summary>
        <div class="guide-collapse__body">#{inner_html}</div>
      </details>
    HTML
  end

  def render_var(entry)
    name = entry[:attrs]["name"].to_s.strip
    return "" unless name.match?(VAR_NAME_RE)

    label = entry[:attrs]["label"].to_s
    label = name.tr("_-", " ").upcase_first if label.empty?
    placeholder = entry[:attrs]["placeholder"].to_s
    <<~HTML
      <label class="guide-var">
        <span class="guide-var__label">#{ERB::Util.html_escape(label)}</span>
        <input type="text"
               class="guide-var__input"
               maxlength="120"
               autocomplete="off"
               spellcheck="false"
               placeholder="#{ERB::Util.html_escape(placeholder)}"
               data-guide-var-input="#{name}"
               data-action="input->mission-guide-variables#update">
      </label>
    HTML
  end

  # Until the reader types a value, the span shows the variable name as a
  # muted placeholder (the --empty modifier); the Stimulus controller swaps in
  # the real value and drops the modifier.
  def render_var_ref(entry, slugged:)
    name = entry[:content].to_s.strip
    return "" unless name.match?(VAR_NAME_RE)

    mode = slugged ? "slug" : "raw"
    %(<span class="guide-var-ref guide-var-ref--empty" data-guide-var-ref="#{name}" data-guide-var-mode="#{mode}">#{name}</span>)
  end
end
