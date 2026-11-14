# Development-only sample data for /admin/virality_reviews.
namespace :virality do
  desc "Create sample viral-mention submissions for the virality review page"
  task seed: :environment do
    abort "Refusing to seed outside development." unless Rails.env.development?

    seeder = ViralitySeeder.new
    abort "Already seeded. Run virality:unseed first." if seeder.seeded?

    seeder.run
    puts seeder.report
  end

  desc "Remove everything virality:seed created"
  task unseed: :environment do
    abort "Refusing to unseed outside development." unless Rails.env.development?

    puts ViralitySeeder.new.destroy_all
  end
end

class ViralitySeeder
  TAG = "virality-seed".freeze
  DOMAIN = "virality.seed".freeze
  SLACK_PREFIX = "UVIRALSEED".freeze

  # A method, not a constant: rake loads this file before the models exist.
  def self.specs
    [
    {
      title: "Orbit Tabs", slug: "orbit-tabs",
      mentions: [
        { url: "https://www.reddit.com/r/SideProject/comments/1k9x2qa/i_made_a_tab_manager_that_puts_your_tabs_in_orbit/",
          submitter_notes: "hit the front page of r/SideProject, ~1.3k upvotes last i checked", state: :pending }
      ]
    },
    {
      title: "Nebula Notes", slug: "nebula-notes",
      mentions: [
        { url: "https://news.ycombinator.com/item?id=41827733",
          submitter_notes: "Show HN post, was on the front page for a few hours", state: :pending },
        { url: "https://github.com/nebula-notes/nebula-notes",
          submitter_notes: "repo got 140 stars after the HN post", state: :approved, tier: "great",
          platform: "GitHub", metric_name: "stars", metric_value: 140, days_ago: 9 }
      ]
    },
    {
      title: "Comet Clock", slug: "comet-clock",
      mentions: [
        { url: "https://www.youtube.com/watch?v=q3Xh7RkVb2c",
          submitter_notes: "build video on my channel, 3.4k views", state: :pending }
      ]
    },
    {
      title: "Starboard Synth", slug: "starboard-synth",
      mentions: [
        { url: "https://www.tiktok.com/@starboardsynth/video/7431982274610527530",
          submitter_notes: "tiktok demo of the synth, 18k views", state: :pending }
      ]
    },
    {
      title: "Gravity Well", slug: "gravity-well",
      mentions: [
        { url: "https://x.com/gravitywelldev/status/1853344091827331112",
          submitter_notes: "tweet with the gameplay gif, 74 likes", state: :pending }
      ]
    },
    {
      title: "Pulsar Pomodoro", slug: "pulsar-pomodoro",
      mentions: [
        { url: "https://pulsar-pomodoro.example.test",
          submitter_notes: "my website gets a lot of visitors!!", state: :pending }
      ]
    },
    {
      title: "Lunar Lens", slug: "lunar-lens",
      mentions: [
        { url: "https://www.instagram.com/reel/DBx9kQ2Ov7Z/",
          submitter_notes: "reel showing the app, 41k views", state: :pending }
      ]
    },
    {
      title: "astro-fmt", slug: "astro-fmt",
      mentions: [
        { url: "https://www.npmjs.com/package/astro-fmt",
          submitter_notes: "2.1k weekly downloads on npm", state: :pending,
          extra_links: "https://npm-stat.com/charts.html?package=astro-fmt" }
      ]
    },
    {
      title: "Meteor Mobs", slug: "meteor-mobs",
      mentions: [
        { url: "https://modrinth.com/mod/meteor-mobs",
          submitter_notes: "fabric mod, 6k downloads", state: :pending,
          extra_links: "https://www.curseforge.com/minecraft/mc-mods/meteor-mobs" }
      ]
    },
    {
      title: "Quasar Queue", slug: "quasar-queue",
      mentions: [
        { url: "https://dev.to/quasarqueue/building-a-job-queue-in-a-weekend-3k2f",
          submitter_notes: "got featured in the dev.to weekly newsletter", state: :pending }
      ]
    },
    {
      title: "Eclipse Editor", slug: "eclipse-editor", ship_status: "submitted",
      mentions: [
        { url: "https://www.reddit.com/r/programming/comments/1kb0aa1/eclipse_editor_a_tiny_modal_editor/",
          submitter_notes: "posted before my ship got reviewed, 600 upvotes", state: :pending }
      ]
    },
    {
      title: "Solar Sketch", slug: "solar-sketch",
      mentions: [
        { url: "https://bsky.app/profile/solarsketch.bsky.social/post/3l7vxq2kd4s2a",
          submitter_notes: "bluesky post, 90 likes and a bunch of reposts", state: :triaged,
          internal_notes: "Likes look real, mostly art accounts. README credit still missing.",
          review_checklist: [ "Original work", "Built during Stardance", "Outside Hack Club" ],
          extra_links: "https://bsky.app/profile/solarsketch.bsky.social/post/3l7wa81mmzc2x" }
      ]
    },
    {
      title: "Void Runner", slug: "void-runner",
      mentions: [
        { url: "https://www.youtube.com/watch?v=Zt8pLm0Qw4E",
          submitter_notes: "a youtuber played my game!! 62k views", state: :on_hold,
          internal_notes: "Asked in DM whether the YouTuber was paid. Waiting on reply." }
      ]
    },
    {
      title: "Ion Drive", slug: "ion-drive",
      mentions: [
        { url: "https://github.com/ion-drive/ion-drive",
          submitter_notes: "130 stars", state: :on_hold,
          internal_notes: "Star history shows +100 in one hour. Possible star farming, checking stargazers." }
      ]
    },
    {
      title: "Hyperspace Habits", slug: "hyperspace-habits",
      mentions: [
        { url: "https://apps.apple.com/us/app/hyperspace-habits/id6739120452",
          submitter_notes: "app store, 450 downloads in the first month", state: :proposed,
          proposed_action: "approve", proposed_tier: "good", platform: "App store", metric_name: "downloads", metric_value: 450,
          review_checklist: ProjectMention::ELIGIBILITY_CHECKS,
          reviewer_notes: ViralityDecision::REPLIES["Well done"] }
      ]
    },
    {
      title: "Cosmic Crates", slug: "cosmic-crates",
      mentions: [
        { url: "https://www.reddit.com/r/rust/comments/1kc3p7z/cosmic_crates_browse_cratesio_like_a_star_map/",
          submitter_notes: "r/rust, 700 upvotes", state: :proposed,
          proposed_action: "approve", proposed_tier: "great", platform: "Reddit", metric_name: "upvotes", metric_value: 712,
          review_checklist: ProjectMention::ELIGIBILITY_CHECKS,
          internal_notes: "Imported from Airtable.", reviewer_notes: ViralityDecision::REPLIES["Well done"] }
      ]
    },
    {
      title: "Asteroid Arcade", slug: "asteroid-arcade",
      mentions: [
        { url: "https://x.com/asteroidarcade/status/1849012357720011010",
          submitter_notes: "12 likes", state: :proposed, proposed_action: "reject",
          platform: "Twitter / X", metric_name: "likes", metric_value: 12,
          reviewer_notes: format(ViralityDecision::REPLIES["Below threshold"], threshold: "Good threshold of 50 likes") }
      ]
    },
    {
      title: "Starlight Shader", slug: "starlight-shader",
      mentions: [
        { url: "https://www.reddit.com/r/godot/comments/1k7f0a2/made_a_starlight_shader/",
          submitter_notes: "r/godot, 40 upvotes", state: :approved, tier: "good",
          platform: "Reddit", metric_name: "upvotes", metric_value: 40, days_ago: 6 },
        { url: "https://www.reddit.com/r/godot/comments/1k7f0a2/made_a_starlight_shader/",
          submitter_notes: "same post but it has more upvotes now", state: :pending }
      ]
    },
    {
      title: "Wormhole Wiki", slug: "wormhole-wiki",
      mentions: [
        { url: "https://www.youtube.com/watch?v=Hk2rX9aVt1s",
          submitter_notes: "showcase video", state: :rejected, days_ago: 4,
          reason: ViralityDecision::REPLIES["Built before Stardance"] }
      ]
    }
    ]
  end

  def initialize(now: Time.current)
    @now = now
    @counts = Hash.new(0)
  end

  def seeded? = projects.exists?

  def run
    ActiveRecord::Base.transaction do
      self.class.specs.each_with_index { |spec, i| build_project(spec, i) }
    end
    self
  end

  def report
    lines = [ "Seeded:" ] + @counts.sort.map { |name, count| format("  %-20s %s", name, count) }
    (lines + [ "", "Review page: /admin/virality_reviews" ]).join("\n")
  end

  def destroy_all
    removed = Hash.new(0)
    ActiveRecord::Base.transaction do
      mentions = ProjectMention.where(project_id: projects.select(:id))
      removed["virality_decisions"] = ViralityDecision.where(project_mention_id: mentions.select(:id)).delete_all
      removed["mentions"] = mentions.delete_all
      removed["ledger_entries"] = LedgerEntry.where(ledgerable_type: "Project", ledgerable_id: projects.select(:id)).delete_all
      removed["memberships"] = Project::Membership.where(project_id: projects.select(:id)).delete_all
      removed["projects"] = projects.destroy_all.size
      # destroy_all rather than delete_all: creating a user spins up dependent
      # records that hold foreign keys back to it.
      removed["users"] = User.where("email LIKE ?", "%@#{DOMAIN}").destroy_all.size
    end
    ([ "Removed:" ] + removed.sort.map { |name, count| format("  %-20s %s", name, count) }).join("\n")
  end

  private

  def track(name) = @counts[name] += 1

  def projects = Project.with_deleted.where("projects.description LIKE ?", "%#{TAG}%")

  def reviewer
    @reviewer ||= User.find_by(email: "reviewer@#{DOMAIN}") || begin
      track("users")
      create_user!(slack_id: "#{SLACK_PREFIX}R", display_name: "seed_virality_reviewer",
                   email: "reviewer@#{DOMAIN}", granted_roles: [ "admin" ])
    end
  end

  def create_user!(**attributes)
    user = User.create!(**attributes, onboarded_at: @now)
    user.create_hack_club_identity!(provider: "hack_club", uid: "dev-#{user.id}", access_token: "dev-access-token")
    user
  end

  def build_project(spec, index)
    owner = create_user!(slack_id: "#{SLACK_PREFIX}#{index}", display_name: spec[:slug].tr("-", "_"),
                         email: "#{spec[:slug]}@#{DOMAIN}")
    track("users")
    project = Project.create!(title: spec[:title],
                              description: "#{TAG} sample project",
                              repo_url: "https://github.com/#{spec[:slug]}/#{spec[:slug]}",
                              demo_url: "https://#{spec[:slug]}.example.test",
                              readme_url: "https://github.com/#{spec[:slug]}/#{spec[:slug]}#readme")
    # AASM refuses direct assignment of its column.
    project.update_columns(ship_status: spec.fetch(:ship_status, "approved"))
    Project::Membership.create!(project: project, user: owner, role: :owner)
    track("projects")

    spec[:mentions].each_with_index do |mention_spec, offset|
      build_mention(project, mention_spec, created_at: @now - (self.class.specs.size - index).days + offset.hours)
    end
    reconcile!(project)
  end

  def build_mention(project, spec, created_at:)
    attributes = spec.except(:state, :tier, :days_ago, :reason)
    mention = project.mentions.create!(attributes.merge(created_at: created_at, updated_at: created_at))
    case spec[:state]
    when :on_hold then mention.update_columns(on_hold_at: created_at + 1.day)
    when :approved, :rejected then decide!(mention, spec)
    end
    track("mentions_#{spec[:state]}")
  end

  def decide!(mention, spec)
    decided_at = @now - spec[:days_ago].days
    approve = spec[:state] == :approved
    mention.update_columns(
      reviewer_id: reviewer.id, reviewer_notes: spec[:reason] || ViralityDecision::REPLIES["Well done"],
      approved_at: (decided_at if approve), rejected_at: (decided_at unless approve),
      approved_tier: (spec[:tier] if approve), review_checklist: (approve ? ProjectMention::ELIGIBILITY_CHECKS : []),
      updated_at: decided_at
    )
    decision = mention.virality_decisions.new(
      action: approve ? "approve" : "reject", tier: spec[:tier], reviewer: reviewer, status: "processed",
      reason: spec[:reason], process_at: decided_at, processed_at: decided_at,
      evidence: { platform: spec[:platform], metric_name: spec[:metric_name], metric_value: spec[:metric_value].to_s,
                  eligibility_confirmed: approve ? "1" : "0" }.compact,
      result: {}
    )
    decision.save!(validate: false)
    decision.update_columns(created_at: decided_at - ViralityDecision::DELAY, updated_at: decided_at)
    track("decisions")
  end

  def reconcile!(project)
    return unless project.mentions.approved.exists?

    PaperTrail.request(whodunnit: reviewer.id.to_s) { Virality::ReconcileBonus.new(project).call }
    track("bonuses_reconciled")
  end
end
