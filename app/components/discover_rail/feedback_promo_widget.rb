# frozen_string_literal: true

module DiscoverRail
  # Static promo card: pitch the feedback form and its stardust raffle. The form
  # opens as a Fillout slider over the page rather than a navigation away.
  class FeedbackPromoWidget < BaseWidget
    register_as :feedback_promo

    FORM_ID = "1UMtrFMC9Xus"
    FORM_DOMAIN = "forms.hackclub.com"
    EMBED_SCRIPT_SRC = "https://server.fillout.com/embed/v1/"
  end
end
