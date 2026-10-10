# Outbound links from the discover rail's promo cards (and the feed's wrong tool one). Each one counts the
# click server-side, so ad blockers and missing JavaScript can't drop it,
# then hands the visitor on to the promoted program.
class PromosController < ApplicationController
  def forge
    track_event DiscoverRail::ForgePromoWidget::CLICK_EVENT
    redirect_to DiscoverRail::ForgePromoWidget::URL, allow_other_host: true, status: :see_other
  end

  def mipmap
    track_event DiscoverRail::MipmapPromoWidget::CLICK_EVENT
    redirect_to DiscoverRail::MipmapPromoWidget::URL, allow_other_host: true, status: :see_other
  end

  def wrong_tool
    track_event Feed::WrongToolPromoComponent::CLICK_EVENT
    redirect_to Feed::WrongToolPromoComponent::URL, allow_other_host: true, status: :see_other
  end
end
