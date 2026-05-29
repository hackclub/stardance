class MarkdownContentComponent < ViewComponent::Base
  include MarkdownHelper

  FLAVORS = {
    standard: { wrapper_class: "markdown-content" },
    guide:    { wrapper_class: "guide-content" }
  }.freeze

  def initialize(markdown:, flavor: :standard)
    raise ArgumentError, "unknown flavor #{flavor.inspect}" unless FLAVORS.key?(flavor)
    @markdown = markdown
    @flavor   = flavor
  end

  def render? = @markdown.present?

  def wrapper_class = FLAVORS.fetch(@flavor)[:wrapper_class]

  def rendered_html
    case @flavor
    when :guide    then MarkdownRenderer.render_guide(@markdown).html.html_safe
    when :standard then md(@markdown)
    else raise ArgumentError, "unknown flavor #{@flavor.inspect}"
    end
  end
end
