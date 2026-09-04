# Development-only sample data for the per-person fraud queue
# (/admin/fraud/subjects). Normal dev data has no pending flags, orders and
# integrity checks sitting on the same people, so the ranking, the per-item
# verdicts and the exclusions all render empty. This builds one person per
# case, including the ones that must NOT appear in the queue.
#
# Everything is tagged with TAG so `fraud_queue:unseed` removes exactly what
# this added and nothing else.
namespace :fraud_queue do
  desc "Create people with flags, shop orders and integrity checks waiting on them"
  task seed: :environment do
    abort "Refusing to seed outside development." unless Rails.env.development?

    seeder = FraudQueueSeeder.new
    seeder.run
    puts seeder.report
  end

  desc "Remove everything fraud_queue:seed created"
  task unseed: :environment do
    abort "Refusing to unseed outside development." unless Rails.env.development?

    puts FraudQueueSeeder.new.destroy_all
  end
end

class FraudQueueSeeder
  TAG = "fraud-queue-seed".freeze
  DOMAIN = "fraudqueue.seed".freeze
  SLACK_PREFIX = "UFRAUDQ".freeze

  FLAG_DETAILS = [
    "Hackatime shows 40 minutes against a 12 hour claim, and the commits all land in one burst.",
    "Whole repo is a rename of the tutorial project. No original work that I can find.",
    "Undeclared AI: the README and every comment read as generated, no disclosure anywhere.",
    "Demo video is someone else's recording, watermark still visible in the corner.",
    "Three ships in one evening, each claiming eight hours of build time."
  ].freeze

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  def initialize(now: Time.current)
    @now = now
    @counts = Hash.new(0)
  end

  def run
    ActiveRecord::Base.transaction do
      build_reporters
      build_flags_only
      build_orders_only
      build_checks_only
      build_all_three
      build_team
      build_deleted_project
      build_banned
      build_out_of_scope
    end
    self
  end

  def report
    lines = [ "Seeded:" ] + @counts.sort.map { |name, count| format("  %-30s %s", name, count) }
    lines += [
      "",
      "Queue: /admin/fraud/subjects",
      "",
      "Expected order (weight x age in days, highest first):",
      "  seed_flags_only     oldest flag, ~30d  -> should sit at the top",
      "  seed_orders_only    on-hold order, 40d",
      "  seed_checks_only    oldest check, 60d",
      "  seed_all_three      all three kinds, and the only one with Telescreen links",
      "  seed_team_lead / seed_team_mate   one flag on a shared project, both listed",
      "  seed_deleted_proj   check on a soft-deleted project",
      "",
      "Must NOT appear: seed_banned (banned), seed_out_of_scope (quality flags",
      "and an awaiting_verification order only).",
      "",
      "Grant yourself access with: User.find_by(display_name: \"...\").grant_role!(:fraud_squad)"
    ]
    lines.join("\n")
  end

  def destroy_all
    removed = Hash.new(0)
    ActiveRecord::Base.transaction do
      users = User.where("email LIKE ?", "%@#{DOMAIN}")
      projects = Project.with_deleted.where("projects.description LIKE ?", "%#{TAG}%")
      posts = Post.where(project_id: projects.select(:id))
      orders = ShopOrder.where(user_id: users.select(:id))
      # Keyed off the tagged body rather than a join through posts: the posts
      # are deleted below, and a relation that reads through them would find
      # nothing by the time the ship events are removed.
      ships = Post::ShipEvent.where("body LIKE ?", "%#{TAG}%")

      removed["integrity_checks"] = Certification::Integrity.where(ship_event_id: ships.select(:id)).delete_all
      removed["reports"] = Project::Report.where(project_id: projects.select(:id)).delete_all
      removed["ledger_entries"] = LedgerEntry.where(user_id: users.select(:id)).delete_all
      removed["shop_orders"] = orders.delete_all
      removed["shop_items"] = ShopItem.where("description LIKE ?", "%#{TAG}%").destroy_all.size
      removed["hackatime_projects"] = User::HackatimeProject.where(user_id: users.select(:id)).delete_all
      removed["memberships"] = Project::Membership.where(project_id: projects.select(:id)).delete_all
      removed["post_views"] = PostView.where(post_id: posts.select(:id)).delete_all
      removed["posts"] = posts.delete_all
      removed["ship_events"] = ships.delete_all
      removed["projects"] = projects.delete_all
      # destroy_all rather than delete_all: creating a user spins up dependent
      # records that hold foreign keys back to it.
      removed["users"] = users.destroy_all.size
    end

    ([ "Removed:" ] + removed.sort.map { |name, count| format("  %-30s %s", name, count) }).join("\n")
  end

  private

  def track(name, count = 1) = @counts[name] += count

  # Integrity flag bitmasks, so the coloured flag pills have something to show.
  # A method rather than a constant: the rake file is loaded before the app's
  # own constants are.
  def check_flags
    integrity = Certification::Integrity
    @check_flags ||= [
      integrity::FLAG_UNKNOWN_FILE,
      integrity::FLAG_CURSOR_STRANGE | integrity::FLAG_NEURALNET,
      integrity::FLAG_NO_HACKATIME_USER,
      integrity::FLAG_ENTROPY_ANOMALY | integrity::FLAG_UNKNOWN_FILE,
      0
    ]
  end

  # Flags need a filer who is not on the project, and the unique index on
  # (reporter_id, project_id) means one report per person per project, so a
  # handful of them cover every project below.
  def build_reporters
    @reporters = 5.times.map do |i|
      find_or_create_user("reporter-#{i}", "seed_reporter_#{i}")
    end
  end

  def build_flags_only
    user = find_or_create_user("flags-only", "seed_flags_only")
    flag_project(user, "Cheap Knockoff", reason: "fraud", age: 30.days, reporter: @reporters[0])
    flag_project(user, "Generated Portfolio", reason: "undeclared_ai", age: 3.days, reporter: @reporters[1])
  end

  def build_orders_only
    user = find_or_create_user("orders-only", "seed_orders_only")
    place_order(user, state: "pending", age: 12.days)
    place_order(user, state: "on_hold", age: 40.days)
  end

  def build_checks_only
    user = find_or_create_user("checks-only", "seed_checks_only")
    [ 20, 45, 60 ].each_with_index do |days, i|
      ship_with_check(user, "Ship #{i + 1}", age: days.days, flags: check_flags[i])
    end
  end

  # The interesting case: every kind of work at once, plus a Hackatime identity
  # and a linked Hackatime project so the Telescreen tools render in full.
  def build_all_three
    user = find_or_create_user("all-three", "seed_all_three")
    project = flag_project(user, "Busy Builder", reason: "External flag", age: 5.days, reporter: @reporters[2])
    place_order(user, state: "pending", age: 2.days)
    ship_with_check(user, "Busy Builder ship", age: 10.days, flags: check_flags[1])
    ship_with_check(user, "Busy Builder reship", age: 55.days, flags: check_flags[3])

    unless user.identities.hackatime.exists?
      track("hackatime_identities")
      user.identities.create!(provider: "hackatime", uid: "99#{user.id}", access_token: "seed-token-#{user.id}")
    end

    unless User::HackatimeProject.exists?(user: user, project: project)
      track("hackatime_projects")
      User::HackatimeProject.create!(user: user, project: project, name: "busy-builder")
    end
  end

  # One flag on a shared project surfaces for every member, because a report
  # names a project and not a person.
  def build_team
    lead = find_or_create_user("team-lead", "seed_team_lead")
    mate = find_or_create_user("team-mate", "seed_team_mate")
    project = flag_project(lead, "Two Person Build", reason: "YSWS project flag", age: 8.days, reporter: @reporters[3])

    unless Project::Membership.exists?(project: project, user: mate)
      track("memberships")
      Project::Membership.create!(project: project, user: mate, role: :contributor)
    end
  end

  # Banning soft-deletes the projects, so a check on one is how the page's
  # "Deleted project" row happens in real data.
  def build_deleted_project
    user = find_or_create_user("deleted-proj", "seed_deleted_proj")
    project = ship_with_check(user, "Since Deleted", age: 15.days, flags: check_flags[0])
    project.update_columns(deleted_at: @now) if project.deleted_at.nil?
  end

  # Has work waiting but is banned, so the queue must skip them.
  def build_banned
    user = find_or_create_user("banned", "seed_banned")
    flag_project(user, "Already Banned", reason: "fraud", age: 25.days, reporter: @reporters[4])
    place_order(user, state: "pending", age: 25.days)
    user.update_columns(banned: true, banned_at: @now, banned_reason: "#{TAG} demo ban")
  end

  # Only the report reasons the fraud team does not own, and an order that is
  # waiting on the buyer rather than a reviewer. Neither belongs in the queue.
  def build_out_of_scope
    user = find_or_create_user("out-of-scope", "seed_out_of_scope")
    flag_project(user, "Just Low Effort", reason: "low_effort", age: 50.days, reporter: @reporters[0])
    flag_project(user, "Broken Demo", reason: "demo_broken", age: 50.days, reporter: @reporters[1])
    place_order(user, state: "awaiting_verification", age: 50.days)
  end

  def find_or_create_user(slug, display_name)
    User.find_by(email: "#{slug}@#{DOMAIN}") || begin
      track("users")
      User.create!(
        slack_id: "#{SLACK_PREFIX}#{slug.upcase.delete('-')}",
        display_name: display_name,
        email: "#{slug}@#{DOMAIN}",
        # Clears the shop-tutorial gate, which otherwise blocks every order.
        has_gotten_free_stickers: true
      )
    end
  end

  def find_or_create_project(user, title)
    Project.with_deleted.find_by(title: "#{title} (#{TAG})") || begin
      track("projects")
      project = Project.create!(title: "#{title} (#{TAG})", description: "#{TAG} demo project")
      Project::Membership.create!(project: project, user: user, role: :owner)
      project
    end
  end

  def flag_project(user, title, reason:, age:, reporter:)
    project = find_or_create_project(user, title)
    return project if Project::Report.exists?(project: project, reporter: reporter)

    track("flags")
    report = Project::Report.create!(
      project: project, reporter: reporter, reason: reason, status: :pending,
      details: FLAG_DETAILS.sample
    )
    report.update_columns(created_at: @now - age, updated_at: @now - age)
    project
  end

  def ship_with_check(user, title, age:, flags:)
    project = find_or_create_project(user, title)
    return project if project.posts.exists?

    track("integrity_checks")
    ship_event = Post::ShipEvent.create!(body: "#{TAG} ship", uploading_attachments: true)
    post = Post.create!(project: project, user: user, postable: ship_event)
    post.update_columns(created_at: @now - age, updated_at: @now - age)
    check = Certification::Integrity.create!(ship_event: ship_event, status: :pending, flags: flags)
    check.update_columns(created_at: @now - age, updated_at: @now - age)
    project
  end

  def place_order(user, state:, age:)
    return if user.shop_orders.where(aasm_state: state).exists?

    track("shop_orders")
    order = user.shop_orders.create!(
      shop_item: shop_item, quantity: 1,
      frozen_address: { "country" => "US", "primary" => true }
    )
    # Set the state directly: the order has to sit in a queue state, and
    # auto-approval would otherwise move a cheap one straight to fulfillment.
    order.update_columns(aasm_state: state, created_at: @now - age, updated_at: @now - age)
    order
  end

  def shop_item
    @shop_item ||= ShopItem.find_by("description LIKE ?", "%#{TAG}%") || begin
      track("shop_items")
      item = ShopItem.new(
        name: "Seeded Fraud Demo Patch", description: "#{TAG} demo item",
        ticket_cost: 0, usd_cost: 12, type: "ShopItem::ThirdPartyPhysical", enabled: true
      )
      item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
      item.save!
      item
    end
  end
end
