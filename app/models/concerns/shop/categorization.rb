# frozen_string_literal: true

# Source of truth for the six top-level shop categories on the hub. Each entry
# maps a slug used in the URL to the human title, the matching ShopItem STI
# types, and a stack of illustration filenames used as the category tile art
# on the hub.
#
# When adding a new STI subclass, slot it into the right `types` array here so
# it shows up in the matching category subpage.
module Shop::Categorization
  DEFINITIONS = {
    "all" => {
      title: "All",
      hub_title: "All",
      types: nil # nil = no filter (everything)
    },
    "grants" => {
      title: "Grants Shop",
      hub_title: "Grants",
      types: %w[ShopItem::HCBGrant ShopItem::HCBPreauthGrant]
    },
    "hq" => {
      title: "HQ Shop",
      hub_title: "HQ",
      types: %w[ShopItem::WarehouseItem ShopItem::HQMailItem ShopItem::LetterMail ShopItem::FreeStickers ShopItem::TutorialNothing]
    },
    "digital" => {
      title: "Digital Shop",
      hub_title: "Digital",
      types: %w[ShopItem::ThirdPartyDigital]
    },
    "locally_fulfilled" => {
      title: "Locally Fulfilled Shop",
      hub_title: "Locally Fulfilled",
      types: %w[ShopItem::ThirdPartyPhysical ShopItem::SpecialFulfillmentItem]
    },
    "made_by_hack_clubbers" => {
      title: "Made by Hack Clubbers Shop",
      hub_title: "Made by Hack Clubbers",
      types: %w[ShopItem::HackClubberItem]
    }
  }.freeze

  SLUGS = DEFINITIONS.keys.freeze

  module_function

  def find(slug) = DEFINITIONS[slug.to_s]

  def title_for(slug)
    find(slug)&.dig(:title) || "Shop"
  end

  def types_for(slug)
    find(slug)&.dig(:types)
  end

  def filter(items, slug)
    types = types_for(slug)
    return items if types.nil?

    items.select { |item| types.include?(item.type) }
  end
end
