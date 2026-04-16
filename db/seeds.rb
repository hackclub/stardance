# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

free_stickers = ShopItem::FreeStickers.find_or_create_by!(name: "Free Stickers!") do |item|
  item.one_per_person_ever = true
  item.description = "we'll actually send you these!"
  item.ticket_cost = 10
  downloaded_image = URI.parse("https://placecats.com/300/200").open
  item.image.attach(io: downloaded_image, filename: "sticker.png")
end
free_stickers.update!(ticket_cost: 10) if free_stickers.ticket_cost != 10

# Create the current sidequests
Sidequest.find_or_create_by!(slug: "extension") do |sq|
  sq.title = "Extensions"
  sq.description = "Unlock a Chrome Developer License in the shop! Must have a GitHub release with a .crx file to qualify."
  sq.expires_at = Date.new(2026, 2, 20)
end

# Chrome Webstore License - requires extension sidequest achievement
chrome_license = ShopItem::HCBGrant.find_or_create_by!(name: "Chrome Webstore License") do |item|
  item.description = "A $5 grant to pay for your Chrome Web Store developer registration fee"
  item.ticket_cost = 0
  downloaded_image = URI.parse("https://placecats.com/300/200").open
  item.image.attach(io: downloaded_image, filename: "chrome-webstore.png")
end
chrome_license.update!(requires_achievement: [ "sidequest_extension" ])

ram_grant_50 = ShopItem::HCBGrant.find_or_create_by!(name: "$50 Ram/Storage Grant") do |item|
  item.description = "A $50 grant to help you upgrade your setup"
  item.ticket_cost = 0
  downloaded_image = URI.parse("https://placecats.com/300/200").open
  item.image.attach(io: downloaded_image, filename: "ram-grant-50.png")
end
ram_grant_50.update!(requires_achievement: [ "sidequest_optimization" ])

ram_grant_100 = ShopItem::HCBGrant.find_or_create_by!(name: "$100 Ram/Storage Grant") do |item|
  item.description = "A $100 grant to help you upgrade your setup"
  item.ticket_cost = 0
  downloaded_image = URI.parse("https://placecats.com/300/200").open
  item.image.attach(io: downloaded_image, filename: "ram-grant-100.png")
end
ram_grant_100.update!(requires_achievement: [ "sidequest_optimization" ])

Sidequest.find_or_create_by!(slug: "challenger") do |sq|
  sq.title = "Challenger Center"
  sq.description = "Build a space-themed project for the Challenger Center space challenge!"
end

Sidequest.find_or_create_by!(slug: "webos") do |sq|
  sq.title = "webOS"
  sq.description = "Build a project for the webOS sidequest! Unlock webOS prizes in the shop."
end

Sidequest.find_or_create_by!(slug: "optimization") do |sq|
  sq.title = "Optimization"
  sq.description = "Build and ship a project for the Optimization sidequest to unlock Optimization prizes in the shop."
end

Sidequest.find_or_create_by!(slug: "caffeinated") do |sq|
  sq.title = "Caffeinated"
  sq.description = "Build and ship a website to unlock a caffeine grant in the shop."
end

Sidequest.find_or_create_by!(slug: "physics_lab") do |sq|
  sq.title = "Physics Lab"
  sq.description = "Build an interactive physics project and ship it on Stardance to unlock physics prizes in the shop."
end
Sidequest.find_or_create_by!(slug: "the_hackazine") do |sq|
  sq.title = "The Hackazine"
  sq.description = "This January: make a page for your project and get it in the Hack Club 2025 magazine! Join #magazine and submit before January 22nd. Projects selected for the magazine receive 50 cookies + stickers! Please note, magazine submissions have 0% AI tolerance."
  sq.expires_at = Date.new(2025, 1, 22)
end

Sidequest.find_or_create_by!(slug: "borked_ui_jam") do |sq|
  sq.title = "Borked UI Jam"
  sq.description = "Running until January 25th — make a project with delightfully broken UI/UX and submit it for the Borked UI Jam! The top 5 best (worst) projects will receive cookies + other prizes. Check out #borked for more details."
  sq.expires_at = Date.new(2025, 1, 25)
end

Sidequest.find_or_create_by!(slug: "converge") do |sq|
  sq.title = "Converge"
  sq.description = "Build a Slack or Discord bot that does something useful or creative. Ship it on Stardance and submit it to unlock Converge prizes in the shop!"
end

Sidequest.find_or_create_by!(
  title: "Lock in",
  slug: "lockin",
  description: "Work 10 hrs a week for 4 weeks without missing an hour. You get 120 cookies & unlock some shop items.",
  expires_at: Date.new(2026, 4, 30)
)

# webOS shop items - require webOS sidequest achievement
webos_stickers = ShopItem.find_or_create_by!(id: 95) do |item|
  item.name = "webOS Stickers"
  item.description = "webOS stickers"
  item.type = "ShopItem::LetterMail"
  item.ticket_cost = 0
  downloaded_image = URI.parse("https://placecats.com/300/200").open
  item.image.attach(io: downloaded_image, filename: "webos-stickers.png")
end
webos_stickers.update!(requires_achievement: [ "sidequest_webos" ])

neocities_sub = ShopItem.find_or_create_by!(id: 96) do |item|
  item.name = "Neocities Subscription"
  item.description = "Neocities subscription"
  item.type = "ShopItem::HCBGrant"
  item.ticket_cost = 0
  downloaded_image = URI.parse("https://placecats.com/300/200").open
  item.image.attach(io: downloaded_image, filename: "neocities.png")
end
neocities_sub.update!(requires_achievement: [ "sidequest_webos" ])

chromebook = ShopItem.find_or_create_by!(id: 97) do |item|
  item.name = "Chromebook"
  item.description = "Chromebook"
  item.type = "ShopItem::ThirdPartyPhysical"
  item.ticket_cost = 0
  downloaded_image = URI.parse("https://placecats.com/300/200").open
  item.image.attach(io: downloaded_image, filename: "chromebook.png")
end
chromebook.update!(requires_achievement: [ "sidequest_webos" ])

user = User.find_or_create_by!(email: "max@hackclub.com", slack_id: "U09UQ385LSG")
user.make_super_admin!
user.make_admin!

# Load comprehensive development seed in development environments
if Rails.env.development? && ENV.fetch("USE_BIG_SEED", false)
  puts "Loading comprehensive development seed..."
  load Rails.root.join('db', 'seeds', 'dev_full_seed.rb')
end
