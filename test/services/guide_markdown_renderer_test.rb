require "test_helper"

class GuideMarkdownRendererTest < ActiveSupport::TestCase
  def render(text)
    GuideMarkdownRenderer.render(text)
  end

  # --- basic markdown --------------------------------------------------------

  test "renders plain paragraphs" do
    result = render("Hello world")
    assert_includes result.html, "<p>Hello world</p>"
  end

  test "renders strong, em, code, lists" do
    result = render("**bold** and *italic* and `code`\n\n- one\n- two")
    assert_includes result.html, "<strong>bold</strong>"
    assert_includes result.html, "<em>italic</em>"
    assert_includes result.html, "<code>code</code>"
    assert_includes result.html, "<li>one</li>"
  end

  test "renders tables" do
    md = "before\n\n| a | b |\n| - | - |\n| 1 | 2 |\n\nafter"
    assert_includes render(md).html, "<table"
  end

  # --- safety ----------------------------------------------------------------

  test "strips raw script tags" do
    html = render("hello <script>alert(1)</script> world").html
    refute_includes html, "<script"
    refute_includes html, "</script"
  end

  test "strips raw iframe tags written by author" do
    html = render("here <iframe src='https://evil.example.com'></iframe>").html
    refute_includes html, "<iframe"
    refute_includes html, "evil.example.com"
  end

  test "strips javascript: protocol in links" do
    html = render("[click](javascript:alert(1))").html
    refute_includes html, "javascript:"
  end

  test "strips style attributes" do
    html = render("<p style='color:red'>hi</p>").html
    refute_includes html, "style="
  end

  test "strips event handler attributes" do
    html = render("<a href='https://example.com' onclick='alert(1)'>x</a>").html
    refute_includes html, "onclick"
  end

  test "strips arbitrary class attributes from raw HTML in markdown" do
    html = render("<div class='guide-callout guide-callout--danger'>fake danger</div>").html
    refute_includes html, "guide-callout--danger"
  end

  # --- block shortcodes: callout --------------------------------------------

  test "callout shortcode renders with info type by default" do
    md = <<~MD
      :::callout
      hello
      :::
    MD
    html = render(md).html
    assert_includes html, %(class="guide-callout guide-callout--info")
    assert_includes html, "<p>hello</p>"
  end

  test "callout shortcode respects type attr" do
    md = <<~MD
      :::callout type="warning"
      heads up
      :::
    MD
    html = render(md).html
    assert_includes html, "guide-callout--warning"
  end

  test "callout shortcode rejects unknown type and falls back to info" do
    md = <<~MD
      :::callout type="explode"
      x
      :::
    MD
    html = render(md).html
    assert_includes html, "guide-callout--info"
    refute_includes html, "guide-callout--explode"
  end

  test "callout shortcode renders title" do
    md = <<~MD
      :::callout type="tip" title="Pro tip"
      body
      :::
    MD
    html = render(md).html
    assert_includes html, "guide-callout__title"
    assert_includes html, "Pro tip"
  end

  # --- block shortcodes: sibling --------------------------------------------

  test "two sibling top-level callouts both render" do
    md = <<~MD
      :::callout type="info"
      First callout
      :::

      :::callout type="warning"
      Second callout
      :::
    MD
    html = render(md).html
    assert_includes html, "guide-callout--info"
    assert_includes html, "guide-callout--warning"
    assert_includes html, "First callout"
    assert_includes html, "Second callout"
    refute_includes html, "[[GUIDE_BLOCK"
  end

  # --- block shortcodes: nested ---------------------------------------------

  test "callout shortcode can nest inside collapse" do
    md = <<~MD
      :::collapse summary="See more"
      :::callout type="tip"
      nested
      :::
      :::
    MD
    html = render(md).html
    assert_includes html, "guide-collapse"
    assert_includes html, "guide-callout--tip"
    assert_includes html, "nested"
  end

  # --- block shortcodes: collapse ------------------------------------------

  test "collapse renders details/summary" do
    md = <<~MD
      :::collapse summary="Why?"
      Because.
      :::
    MD
    html = render(md).html
    assert_includes html, "<details"
    assert_includes html, "<summary"
    assert_includes html, "Why?"
    assert_includes html, "Because."
  end

  test "collapse summary escapes html" do
    md = <<~MD
      :::collapse summary="<img src=x onerror=alert(1)>"
      body
      :::
    MD
    html = render(md).html
    refute_includes html, "<img"
    refute_match(/<[^>]*onerror=/, html)
    assert_includes html, "&lt;img"
  end

  # --- inline shortcodes ----------------------------------------------------

  test "kbd inline shortcode" do
    result = render("Press ::kbd[Ctrl+S] to save")
    assert_includes result.html, %(<kbd class="guide-kbd">Ctrl+S</kbd>)
  end

  test "mark inline shortcode" do
    result = render("This is ::mark[important]")
    assert_includes result.html, %(<mark class="guide-mark">important</mark>)
  end

  test "inline shortcode escapes content" do
    result = render("::kbd[<script>]")
    refute_includes result.html, "<script>"
  end

  test "unknown inline shortcode is stripped" do
    result = render("::evilshort[x]")
    refute_includes result.html, "evilshort"
    refute_includes result.html, "[x]"
  end

  # --- guide variables --------------------------------------------------------

  test "var block shortcode renders a labelled input" do
    md = <<~MD
      :::var name="project_name" label="What's your project called?" placeholder="my-cool-app"
      :::
    MD
    html = render(md).html
    assert_includes html, %(class="guide-var")
    assert_includes html, "What's your project called?"
    assert_includes html, %(placeholder="my-cool-app")
    assert_includes html, %(data-guide-var-input="project_name")
  end

  test "var block humanizes the name when label is omitted" do
    md = <<~MD
      :::var name="project_name"
      :::
    MD
    assert_includes render(md).html, "Project name"
  end

  test "var block with invalid name renders nothing" do
    md = <<~MD
      :::var name="<bad name>"
      :::
    MD
    html = render(md).html
    refute_includes html, "guide-var"
    refute_includes html, "bad name"
  end

  test "var-ref inline shortcode renders a raw reference span" do
    html = render("Open ::var-ref[project_name] in your editor").html
    assert_includes html, %(data-guide-var-ref="project_name")
    assert_includes html, %(data-guide-var-mode="raw")
    assert_includes html, "guide-var-ref--empty"
  end

  test "var-slug inline shortcode renders a slug reference span" do
    html = render("Run `cd` into ::var-slug[project_name]").html
    assert_includes html, %(data-guide-var-mode="slug")
  end

  test "var-ref with invalid name is stripped" do
    html = render("::var-ref[<script>]").html
    refute_includes html, "guide-var-ref"
    refute_includes html, "<script>"
  end

  test "var refs expand inside fenced code blocks" do
    md = <<~MD
      ```bash
      npx create-app ::var-slug[project_name]
      ```
    MD
    html = render(md).html
    assert_includes html, %(data-guide-var-ref="project_name")
    refute_includes html, "GUIDE_INLINE"
  end

  test "var refs expand inside inline code" do
    html = render("Run `cd ::var-slug[project_name]` next").html
    assert_includes html, %(data-guide-var-ref="project_name")
    refute_includes html, "GUIDE_INLINE"
  end

  test "unknown block shortcode is stripped" do
    md = <<~MD
      before

      :::nope
      x
      :::

      after
    MD
    html = render(md).html
    assert_includes html, "before"
    assert_includes html, "after"
    refute_includes html, "nope"
  end

  # --- h2 auto-sectioning and outline ---------------------------------------

  test "wraps h2 sections in section element with index" do
    md = <<~MD
      ## Setup

      do this

      ## Database

      do that
    MD
    result = render(md)
    assert_includes result.html, %(<section class="guide-section" data-section-index="0">)
    assert_includes result.html, %(<section class="guide-section" data-section-index="1">)
  end

  test "extracts outline from h2 headings" do
    md = <<~MD
      ## Setup

      ...

      ## Database schema

      ...
    MD
    outline = render(md).outline
    assert_equal 2, outline.length
    assert_equal "Setup", outline[0][:text]
    assert_equal "Database schema", outline[1][:text]
    assert_equal "section-setup", outline[0][:id]
    assert_equal "section-database-schema", outline[1][:id]
  end

  test "h2 elements get id matching outline id" do
    md = "## Hello world\n\ncontent"
    html = render(md).html
    assert_includes html, %(id="section-hello-world")
  end

  test "outline is empty when no h2s" do
    assert_equal [], render("just a paragraph").outline
  end

  test "content before first h2 is preserved outside section" do
    md = <<~MD
      intro paragraph

      ## First

      content
    MD
    html = render(md).html
    assert_includes html, "intro paragraph"
    assert_includes html, "data-section-index=\"0\""
  end

  test "duplicate h2 headings get suffixed slugs and matching outline ids" do
    md = "## Setup\n\nA\n\n## Setup\n\nB"
    result = render(md)
    assert_equal "section-setup",   result.outline[0][:id]
    assert_equal "section-setup-2", result.outline[1][:id]
    assert_includes result.html, %(id="section-setup")
    assert_includes result.html, %(id="section-setup-2")
  end

  # --- post-process ---------------------------------------------------------

  test "external links get target and rel" do
    html = render("[link](https://example.com)").html
    assert_includes html, %(target="_blank")
    assert_includes html, %(rel="noopener noreferrer")
  end

  test "images get lazy loading attrs" do
    html = render("![alt](https://example.com/x.png)").html
    assert_includes html, %(loading="lazy")
    assert_includes html, %(decoding="async")
    assert_includes html, %(referrerpolicy="no-referrer")
  end

  # --- edge cases -----------------------------------------------------------

  test "blank text returns blank result" do
    result = render("")
    assert_equal "", result.html
    assert_equal [], result.outline
  end

  test "shortcode with no attrs parses cleanly" do
    md = ":::callout\nbody\n:::"
    html = render(md).html
    assert_includes html, "guide-callout--info"
  end

  # --- fenced code blocks ---------------------------------------------------

  test "fenced code block with language gets syntax-highlighted via rouge" do
    md = <<~MD
      ```js
      const x = 1;
      ```
    MD
    html = render(md).html
    # Rouge emits .kd for declaration keywords; the language class lives on
    # the <code> wrapper.
    assert_includes html, %(class="guide-code")
    assert_includes html, %(class="language-javascript")
    assert_includes html, %(<span class="kd">const</span>)
  end

  test "fenced code block falls back to plain text for unknown languages" do
    md = <<~MD
      ```someweirdlang
      no highlighter for this
      ```
    MD
    html = render(md).html
    assert_includes html, "guide-code"
    assert_includes html, "no highlighter for this"
    # No token spans because rouge's plaintext lexer doesn't add classes.
    refute_match(/<span class="k[a-z]?">/, html)
  end

  test "fenced code block with no language is left as the default pre/code" do
    md = <<~MD
      ```
      plain code
      ```
    MD
    html = render(md).html
    # No language hint → no rouge processing → no .guide-code wrapper.
    refute_includes html, "guide-code"
    assert_includes html, "plain code"
    assert_includes html, "<pre>"
  end

  test "code block contents are html-escaped" do
    md = <<~MD
      ```html
      <script>alert(1)</script>
      ```
    MD
    html = render(md).html
    refute_includes html, "<script>alert"
    assert_includes html, "&lt;script&gt;"
  end

  # --- marker spoofing ------------------------------------------------------

  test "user-typed block marker does not replay a real block" do
    md = <<~MD
      :::callout type="warning"
      real callout body
      :::

      [[GUIDE_BLOCK:0]]
    MD
    html = render(md).html
    # Real callout body appears once; the unsalted marker the user typed
    # passes through as plain text (safe — brackets are fine in HTML) and
    # critically does not trigger a second expansion.
    assert_equal 1, html.scan("real callout body").length
    assert_includes html, "[[GUIDE_BLOCK:0]]"
  end

  test "user-typed inline marker does not replay a real inline shortcode" do
    md = "Press ::kbd[Ctrl+S]. Stray: [[GUIDE_INLINE:0]]"
    html = render(md).html
    assert_equal 1, html.scan(%(<kbd class="guide-kbd">Ctrl+S</kbd>)).length
  end

  test "user-typed code marker inside a fenced block does not replay code" do
    md = <<~MD
      ```js
      const real = 1;
      ```

      ```txt
      [[GUIDE_CODE:0]]
      ```
    MD
    html = render(md).html
    assert_equal 1, html.scan("const").length
  end

  test "out-of-range block marker noops instead of crashing" do
    salt = SecureRandom.hex(8)
    md = "before [[GUIDE_BLOCK:#{salt}:99]] after"
    html = render(md).html
    assert_includes html, "before"
    assert_includes html, "after"
  end

  # --- id attribute --------------------------------------------------------

  test "author-supplied id attribute on inline html is stripped" do
    html = render("<p id='evil'>x</p>").html
    refute_includes html, %(id="evil")
  end

  test "auto-generated section h2 id still rendered" do
    html = render("## Hello\n\nx").html
    assert_includes html, %(id="section-hello")
  end

  # --- code language class -------------------------------------------------

  test "language class on rouge output is alphanumeric only" do
    md = "```js\nconst x = 1;\n```\n"
    html = render(md).html
    match = html.match(/class="language-([^"]+)"/)
    assert match
    assert_match(/\A[a-z0-9_-]+\z/i, match[1])
  end
end
