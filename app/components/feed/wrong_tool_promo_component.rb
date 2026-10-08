# frozen_string_literal: true

module Feed
  # wrong tool's ad, at the top of the home feed: a little spreadsheet where a rocket
  # made of cells flies through a field of cell stars (a space game in the
  # wrong tool), and that you can steer by pointing at a row. In wrong tool's
  # own Sheets look, like the Crescent ad wears Crescent's. Behind the
  # :wrong_tool_promo flag, and gone once wrong tool ends, or once you hide it.
  class WrongToolPromoComponent < ViewComponent::Base
    URL = "https://wrong.hackclub.com/?utm_source=stardance&utm_medium=feed&utm_campaign=launch"
    # Ahoy event recorded by PromosController#wrong_tool on every click.
    CLICK_EVENT = "wrong_tool_promo_clicked"
    # The last day of wrong tool; the ad stops showing after it.
    ENDS_ON = Date.new(2026, 10, 20)
    # The sheet's size; _wrong_tool_promo.scss lays out this many columns.
    COLUMNS = ("A".."N").to_a.freeze
    ROWS = 6

    def render?
      Date.current <= ENDS_ON && helpers.platform_ads_enabled?(helpers.try(:current_user)) &&
        Flipper.enabled?(:wrong_tool_promo, helpers.try(:current_user))
    end
  end
end
