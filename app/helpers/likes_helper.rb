module LikesHelper
  # Renders the filled "liked" heart with its gradient id namespaced to the
  # record. Many hearts render on one page, and a shared `url(#id)` fill
  # reference resolves to the first matching gradient in the document — which
  # sits inside a display:none icon until that card is liked — leaving every
  # other liked heart painted with an empty fill. Namespacing the id per
  # likeable avoids the collision.
  def like_fill_icon(likeable, css_class:)
    inline_svg_tag("icons/like-fill.svg", class: css_class)
      .gsub("stardance-like-fill", "stardance-like-fill-#{dom_id(likeable)}")
      .html_safe
  end
end
