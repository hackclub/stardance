# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

user = User.find_or_create_by!(email: "kartikey@hackclub.com", slack_id: "U05F4B48GBF")
user.grant_role!(:super_admin)
user.grant_role!(:admin)

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

# Seed default shop items
ShopItem::FreeStickers.find_or_create_by!(name: "Stickers!!") do |item|
  item.description = "we'll actually send you these!"
  item.ticket_cost = 10
  item.enabled = true
  item.one_per_person_ever = true
  item.image.attach(
    io: File.open(Rails.root.join("app/assets/images/free_sticker.avif")),
    filename: "free_sticker.avif",
    content_type: "image/avif"
  )
end
