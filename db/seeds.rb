# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

seed_admin_email = "kartikey@hackclub.com"
seed_admin_slack_id = "U05F4B48GBF"

email_user = User.find_by("LOWER(email) = ?", seed_admin_email.downcase)
slack_user = User.find_by(slack_id: seed_admin_slack_id)

if email_user.present? && slack_user.present? && email_user != slack_user
  raise "Cannot seed admin user: #{seed_admin_email} and #{seed_admin_slack_id} belong to different users"
end

user = email_user || slack_user || User.new
user.email ||= seed_admin_email
user.slack_id ||= seed_admin_slack_id
if user.display_name.blank?
  display_name_base = "kartikey"
  display_name_candidate = display_name_base
  display_name_suffix = 2

  while User.where.not(id: user.id).where("LOWER(display_name) = ?", display_name_candidate.downcase).exists?
    display_name_candidate = "#{display_name_base}_#{display_name_suffix}"
    display_name_suffix += 1
  end

  user.display_name = display_name_candidate
end
user.save!
user.grant_role!(:super_admin)
user.grant_role!(:admin)

stardance_project = Project.find_or_create_by!(title: "Stardance") do |p|
  p.description = "The Stardance program project."
  p.ship_status = "draft"
end

Project::Membership.find_or_create_by!(project: stardance_project, user: user) do |m|
  m.role = :owner
end

# ---------------------------------------------------------------------------
# Base seed: "Make a Slack Bot" — the canonical first mission. Kept intact
# across reseeds via find_or_create_by!; admins who edit the mission or
# guide via the manage UI keep their edits.
# ---------------------------------------------------------------------------
SLACK_MISSION_GUIDE_JS = File.read(Rails.root.join("db/sample_data/slack_bot_guide_js.md"))

slack_mission = Mission.find_or_create_by!(slug: "slack-bot") do |m|
  m.name        = "Make a Slack Bot"
  m.description = "Make a slack bot that can respond to custom slash commands!"
  m.difficulty  = "beginner"
  m.enabled     = false
  m.estimated_completion_minutes = 90
  m.achievement_name        = "I slacked off"
  m.achievement_description = "Made a slack bot through the slack bot mission!"
  m.default_project_title       = "My first slack bot!"
  m.default_project_description = "This bot isn't slacking off, it replies to messages 24/7!"
  m.submission_guide = <<~MD
    - Your bot is live and responds to messages
    - There are at least 3 different commands / functions
    - Your commands don't collide with anyone elses'
    - Your bot is live 24/7, even when your laptop is closed
  MD
end

# Default JavaScript guide. Idempotent — won't overwrite an existing one
# (admins who've edited via the manage UI keep their edits).
Mission::GuideVariant.find_or_create_by!(mission: slack_mission, language: "JavaScript") do |v|
  v.body     = SLACK_MISSION_GUIDE_JS
  v.position = 0
end

# Enable core feature flags for development/staging
if Rails.env.development? || Rails.env.staging?
  Flipper.enable(:shop_open)
  Flipper.enable(:voting)
  Flipper.enable(:grant_stardust)
end

# Seed shop categories (browseable item types) and sources (origin/fulfilment
# tags). Both lists live in the DB so admins can manage them without code
# changes. The old hardcoded categories conflated item type with fulfilment,
# which misled shoppers — categories now describe what an item is, sources
# describe where it comes from.
[
  { slug: "grants",   title: "Grants Shop",   hub_title: "Grants",   position: 0 },
  { slug: "hardware", title: "Hardware Shop", hub_title: "Hardware", position: 1 },
  { slug: "digital",  title: "Digital Shop",  hub_title: "Digital",  position: 2 },
  { slug: "merch",    title: "Merch Shop",    hub_title: "Merch",    position: 3 },
  { slug: "games",    title: "Games Shop",    hub_title: "Games",    position: 4 }
].each do |attrs|
  ShopCategory.find_or_create_by!(slug: attrs[:slug]) do |c|
    c.title = attrs[:title]
    c.hub_title = attrs[:hub_title]
    c.position = attrs[:position]
  end
end

[
  { slug: "hq",                    title: "HQ",                    position: 0 },
  { slug: "locally_fulfilled",     title: "Locally Fulfilled",     position: 1 },
  { slug: "made_by_hack_clubbers", title: "Made by Hack Clubbers", position: 2 },
  { slug: "third_party_digital",   title: "Third-Party Digital",   position: 3 },
  { slug: "hcb_grant",             title: "HCB Grant",             position: 4 }
].each do |attrs|
  ShopSource.find_or_create_by!(slug: attrs[:slug]) do |s|
    s.title = attrs[:title]
    s.position = attrs[:position]
  end
end

# Seed default shop items
stickers = ShopItem::FreeStickers.find_or_create_by!(name: "Stickers!!") do |item|
  item.description = "Option A — pick this to get a real sticker pack shipped to you."
  item.ticket_cost = 0
  item.enabled = true
  item.one_per_person_ever = true
  item.enabled_xx = true
  item.image.attach(
    io: File.open(Rails.root.join("app/assets/images/free_sticker.avif")),
    filename: "free_sticker.avif",
    content_type: "image/avif"
  )
end

tutorial_nothing = ShopItem::TutorialNothing.find_or_create_by!(name: "Nothing") do |item|
  item.description = "Option B — pick this to skip the freebie and just see how the shop works."
  item.ticket_cost = 0
  item.enabled = true
  item.one_per_person_ever = true
  item.unlisted = true
  item.enabled_xx = true
  item.image.attach(
    io: File.open(Rails.root.join("app/assets/images/idea/question.png")),
    filename: "tutorial_nothing.png",
    content_type: "image/png"
  )
end

# Tag the tutorial items so the shop tutorial flow ("open Merch to pick
# stickers or nothing") has something to show. Other items are categorised
# per-item via the admin UI.
merch_category = ShopCategory.find_by!(slug: "merch")
hq_source = ShopSource.find_by!(slug: "hq")

[ stickers, tutorial_nothing ].each do |item|
  item.shop_categories << merch_category unless item.shop_categories.include?(merch_category)
  item.shop_sources    << hq_source      unless item.shop_sources.include?(hq_source)
end

load Rails.root.join("db/seeds/outpost_ticket.rb")
