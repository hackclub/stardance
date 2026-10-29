# frozen_string_literal: true

# Shop-wide clearance banner. While any item is on sale it shouts about the
# biggest discount and counts down to the first sale ending; between sale days
# it teases the next one instead.
class ShopClearanceBannerComponent < ViewComponent::Base
  SHOUTS = [ "Everything must go", "Final days", "Please take it", "Spend that stardust", "Last call" ].freeze

  # One is picked per render, so the banner says something different each visit.
  LIVE_QUIPS = [
    "Stardance is ending and the stardust has to go <em>somewhere</em>.",
    "Bean was told to clear the warehouse. Bean is <em>panicking</em>.",
    "Everything must go. Yes, <em>even the Blåhaj</em>."
  ].freeze
  UPCOMING_QUIPS = [
    "Bean and Buku have already started fighting over the next batch. <em>Save your stardust.</em>",
    "The next sale isn't even open and they're <em>already squabbling</em>."
  ].freeze

  delegate :live?, :top_percentage, :countdown_to, :decaying?, to: :@sale

  def initialize(items:, show_cta: true, **html_options)
    @html_options = html_options
    @sale = Shop::ClearanceSale.new(items)
    @show_cta = show_cta
  end

  def render?
    @sale.any?
  end

  def sale_title
    @sale.title
  end

  def root_classes
    class_names("clearance-banner", { "clearance-banner--upcoming" => !live? }, @html_options[:class])
  end

  def quip
    (live? ? LIVE_QUIPS : UPCOMING_QUIPS).sample.html_safe
  end

  # The random sale item Bean and Buku are fighting over.
  def tug_item
    @sale.featured_item
  end

  def show_cta?
    @show_cta && live?
  end
end
