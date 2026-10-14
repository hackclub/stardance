# "Nonmachinable" is the USPS term: mail too thick or rigid for machine
# processing (e.g. a Pico taped to cardstock).
class ShopItem::NonmachinableLetterMail < ShopItem::LetterMail
  THESEUS_QUEUE = "stardance-nonmachinable".freeze
  MAX_ITEMS_PER_LETTER = 3
end
