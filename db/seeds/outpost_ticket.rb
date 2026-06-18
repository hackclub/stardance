hq_source = ShopSource.find_by!(slug: "hq")

outpost_ticket = ShopItem::OutpostTicket.find_or_create_by!(name: "Outpost Ticket") do |item|
  item.description = "Your ticket to the Outpost. Unlocked once you have a presentable hardware project."
  item.long_description = "Earn this by building a hardware project worth showing off. Getting your design funded discounts the ticket by your tier — 30% at B, 50% at A, and 100% at S and X — and any overflow goes toward a flight stipend."
  item.ticket_cost = User::OUTPOST_TICKET_BASE
  item.enabled = true
  item.one_per_person_ever = true
  item.enabled_xx = true
  item.requires_achievement = [ "manual_outpost_ticket_approval" ]
  item.image.attach(
    io: File.open(Rails.root.join("app/assets/images/shop/hardware_build_fund.png")),
    filename: "outpost_ticket.png",
    content_type: "image/png"
  )
end

hardware_category = ShopCategory.find_by(slug: "hardware")
outpost_ticket.shop_categories << hardware_category if hardware_category && !outpost_ticket.shop_categories.include?(hardware_category)
outpost_ticket.shop_sources    << hq_source        unless outpost_ticket.shop_sources.include?(hq_source)
