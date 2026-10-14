# Development-only sample data for the Super Mega Dashboard.
#
# Every panel needs items spread across a 90 day window in both open and
# decided states, which normal dev data never has. Everything created here is
# tagged with SEED_TAG so `mega_dashboard:unseed` can remove exactly what this
# added and nothing else.
namespace :mega_dashboard do
  SEED_TAG = "megadash-seed".freeze
  SEED_EMAIL_DOMAIN = "megadash.seed".freeze
  SEED_SLACK_PREFIX = "USEED".freeze
  WINDOW_DAYS = 90

  desc "Create sample data so every Super Mega Dashboard panel has something to show"
  task seed: :environment do
    abort "Refusing to seed outside development." unless Rails.env.development?

    if User.where("email LIKE ?", "%@#{SEED_EMAIL_DOMAIN}").exists?
      abort "Seed data is already present. Run mega_dashboard:unseed first, since re-seeding stacks rows instead of converging."
    end

    seeder = MegaDashboardSeeder.new
    seeder.run
    puts seeder.report
  end

  desc "Remove everything mega_dashboard:seed created"
  task unseed: :environment do
    abort "Refusing to unseed outside development." unless Rails.env.development?

    puts MegaDashboardSeeder.new.destroy_all
  end
end

class MegaDashboardSeeder
  TAG = "megadash-seed".freeze
  DOMAIN = "megadash.seed".freeze
  SLACK_PREFIX = "USEED".freeze
  DAYS = 90

  # Shapes measured off the production mirror on 2026-08-11. Depths are scaled
  # down to dev size, but the ratios and latency curves are kept as-is: those
  # are what make the panels read like the real thing. Latencies are given as
  # [median_hours, p90_hours] because every queue in production has a heavy
  # right tail (ship certs sit at 3h median against a 72h p90), which a uniform
  # random spread completely fails to reproduce.
  PROD = {
    ship_cert: { pending: 14, unclaimed_rate: 0.97, decided: 26, latency: [ 3.0, 71.9 ], approve_rate: 0.87 },
    ysws: { pending: 18, unclaimed_rate: 0.64, decided: 14, latency: [ 480.6, 943.4 ], approve_rate: 0.88 },
    funding: { pending: 10, unclaimed_rate: 0.7, decided: 8, latency: [ 941.7, 2000.0 ], approve_rate: 0.14 },
    mission: { pending: 9, unclaimed_rate: 0.81, decided: 18, latency: [ 18.5, 347.8 ], approve_rate: 0.91 },
    integrity: { pending: 6, decided: 10, latency: [ 12.0, 120.0 ] },
    rating: { latency: [ 126.2, 1117.0 ] },
    payout: { latency: [ 8.4, 60.0 ] },
    fulfillment: { latency: [ 451.7, 1200.0 ] },
    vote: { seconds: [ 151.0, 1733.0 ], repo_rate: 0.234, demo_rate: 0.482, discarded_rate: 0.414,
            scores: { originality: 5.97, technical: 5.83, usability: 5.76, storytelling: 5.57 } },
    # submitted / skipped / expired / assigned
    assignment_mix: { "submitted" => 0.477, "skipped" => 0.432, "expired" => 0.071, "assigned" => 0.020 },
    ban_rate: 0.0434,
    # Production's live shop mix, minus FreeStickers which the panel excludes.
    shop_items: {
      "ShopItem::LetterMail" => 252, "ShopItem::WarehouseItem" => 113,
      "ShopItem::ThirdPartyPhysical" => 99, "ShopItem::ThirdPartyDigital" => 22,
      "ShopItem::HQMailItem" => 11
    },
    order_states: { "fulfilled" => 5667, "awaiting_periodical_fulfillment" => 167, "pending" => 122,
                    "rejected" => 94, "awaiting_verification" => 50, "on_hold" => 31 },
    report_reasons: { "undeclared_ai" => 80, "YSWS project flag" => 36, "low_effort" => 27,
                      "other" => 26, "demo_broken" => 26, "Shipwrights project flag" => 20, "fraud" => 12 },
    star: { pending: 8, marked: 14 },
    certificate: { pending: 6, decided: 14 }
  }.freeze

  def initialize(now: Time.current)
    @now = now
    @counts = Hash.new(0)
    # Deterministic, so re-running produces the same shape and diffs are boring.
    @random = Random.new(20260811)
  end

  def run
    ActiveRecord::Base.transaction do
      build_users
      build_projects
      build_ship_certifications
      build_ysws_reviews
      build_integrity_reviews
      build_funding_requests
      build_mission_submissions
      build_shop
      build_reports
      build_votes_and_payouts
      build_voting_pool
      build_certificates
      build_super_stars
      build_bans
      build_jelly_history
    end
    self
  end

  def report
    ([ "Seeded:" ] + @counts.sort.map { |name, count| format("  %-28s %s", name, count) }).join("\n")
  end

  def destroy_all
    removed = Hash.new(0)
    ActiveRecord::Base.transaction do
      users = User.where("email LIKE ?", "%@#{DOMAIN}")
      projects = Project.where("projects.description LIKE ?", "%#{TAG}%")
      ships = Post::ShipEvent.where(id: Post.where(project_id: projects.select(:id)).select(:postable_id))

      removed["vote_events"] = Vote::Event.where(ship_event_id: ships.select(:id)).delete_all
      removed["vote_assignments"] = Vote::Assignment.where(ship_event_id: ships.select(:id)).delete_all
      removed["votes"] = Vote.where(ship_event_id: ships.select(:id)).delete_all
      removed["ledger_entries"] = LedgerEntry.where(user_id: users.select(:id)).delete_all
      removed["mission_submissions"] = Mission::Submission.with_deleted.where(ship_event_id: ships.select(:id)).delete_all
      removed["integrity"] = Certification::Integrity.where(ship_event_id: ships.select(:id)).delete_all
      removed["ysws_reviews"] = Certification::Ysws.where(project_id: projects.select(:id)).delete_all
      removed["ship_certifications"] = Certification::Ship.where(project_id: projects.select(:id)).delete_all
      removed["funding_requests"] = Certification::FundingRequest.where(project_id: projects.select(:id)).delete_all
      removed["reports"] = Project::Report.where(project_id: projects.select(:id)).delete_all
      removed["shop_orders"] = ShopOrder.where(user_id: users.select(:id)).delete_all
      removed["shop_items"] = ShopItem.where("internal_description LIKE ?", "%#{TAG}%").delete_all
      removed["certificates"] = Certificate.where(user_id: users.select(:id)).delete_all
      removed["paper_trail"] = PaperTrail::Version.where(item_type: "User", item_id: users.pluck(:id).map(&:to_s)).delete_all
      removed["jelly_daily_stats"] = JellyDailyStat.where("recorded_on < ?", Date.current).delete_all
      removed["memberships"] = Project::Membership.where(project_id: projects.select(:id)).delete_all
      removed["posts"] = Post.where(project_id: projects.select(:id)).delete_all
      removed["ship_events"] = Post::ShipEvent.where(id: ships.select(:id)).delete_all
      # destroy_all rather than delete_all: creating a user spins up dependent
      # records (raffle participants and friends) that hold foreign keys.
      removed["projects"] = projects.destroy_all.size
      removed["users"] = users.destroy_all.size
    end

    ([ "Removed:" ] + removed.sort.map { |name, count| format("  %-28s %s", name, count) }).join("\n")
  end

  private

  def track(name, count = 1) = @counts[name] += count

  # Production latencies are heavy-tailed, so a log-normal fitted to the
  # measured median and p90 reproduces them far better than a uniform range.
  def latency_hours(median, p90)
    mu = Math.log(median)
    sigma = Math.log(p90 / median) / 1.2816
    z = Math.sqrt(-2 * Math.log(@random.rand)) * Math.cos(2 * Math::PI * @random.rand)
    [ Math.exp(mu + sigma * z), 0.05 ].max
  end

  def latency(shape) = latency_hours(*PROD.dig(shape, :latency)).hours

  # Picks a key from a {value => weight} hash.
  def weighted(distribution)
    total = distribution.values.sum
    roll = @random.rand * total
    distribution.each { |key, weight| return key if (roll -= weight) <= 0 }
    distribution.keys.last
  end

  # Vote reasons must clear a ten word minimum.
  # Production scores cluster near the middle of the 1..9 range; a uniform draw
  # would flatten the category averages the panel reports.
  def score_near(average)
    (average + (@random.rand - 0.5) * 4).round.clamp(1, 9)
  end

  def sample_vote_reason
    "#{TAG} sample vote reason written to satisfy the ten word minimum requirement"
  end

  # Several models gate creation on a full app flow (a devlog exists, a tier
  # ceiling, a prior state machine step). Seed rows are built directly, so
  # those gates are skipped while the columns stay realistic.
  def save_unvalidated!(record, **columns)
    record.save!(validate: false)
    record.update_columns(columns) if columns.any?
    record
  end

  # Spread across the window, weighted toward recent so the charts have a shape
  # rather than a flat line.
  def ago(max_days = DAYS)
    days = (@random.rand**1.6) * max_days
    @now - days.days - @random.rand(24).hours
  end

  def users = @users ||= User.where("email LIKE ?", "%@#{DOMAIN}").to_a

  def projects = @projects ||= Project.where("projects.description LIKE ?", "%#{TAG}%").to_a

  # Projects are owned through Project::Membership, not a user_id column.
  def owner_of(project)
    @owners ||= {}
    @owners[project.id] ||= project.memberships.owner.first&.user || users.first
  end

  def build_users
    existing = User.where("email LIKE ?", "%@#{DOMAIN}").count
    (30 - existing).times do |i|
      index = existing + i
      User.create!(
        slack_id: "#{SLACK_PREFIX}#{index.to_s.rjust(4, '0')}",
        display_name: "seed_tester_#{index}",
        email: "seed#{index}@#{DOMAIN}",
        created_at: ago
      )
      track("users")
    end
    @users = nil
  end

  def build_projects
    existing = projects.size
    (40 - existing).times do |i|
      owner = users[(existing + i) % users.size]
      project = Project.create!(
        title: "Seed Project #{existing + i}",
        description: "#{TAG} sample project",
        readme_url: "https://example.test/readme",
        demo_url: "https://example.test/demo",
        repo_url: "https://example.test/repo",
        created_at: ago
      )
      Project::Membership.create!(project: project, user: owner, role: :owner)
      track("projects")
    end
    @projects = nil
  end

  # One ship event plus its Post, which is what the rest of the pipeline hangs
  # off. Timestamps are written straight to columns so callbacks can't stamp
  # them back to now.
  def ship_event_for(project, created_at:, **attributes)
    # `uploading_attachments` is the concern's own escape hatch for records
    # created without a real upload.
    ship = Post::ShipEvent.create!(body: "#{TAG} ship", uploading_attachments: true)
    Post.create!(project: project, user: owner_of(project), postable: ship, created_at: created_at)
    ship.update_columns(attributes.merge(created_at: created_at, updated_at: created_at))
    ship.reload
  end

  def build_ship_certifications
    # A partial unique index allows only one pending cert per project, so
    # pending and decided certs are drawn from separate project pools.
    pending_projects = projects.first(8)
    decided_projects = projects[8, 22] || []

    pending_projects.each do |project|
      next if Certification::Ship.exists?(project_id: project.id, status: :pending)

      created = ago(20)
      cert = Certification::Ship.create!(project: project, status: :pending)
      cert.update_columns(created_at: created, updated_at: created,
                          claimed_at: (created + 2.hours if @random.rand > PROD[:ship_cert][:unclaimed_rate]))
      track("ship_certifications")
    end

    decided_projects.each do |project|
      created = ago
      decided = created + latency(:ship_cert)
      next if decided > @now

      cert = Certification::Ship.create!(project: project,
                                         status: @random.rand < PROD[:ship_cert][:approve_rate] ? :approved : :returned)
      cert.update_columns(created_at: created, updated_at: decided,
                          claimed_at: created + (decided - created) * 0.3, decided_at: decided)
      track("ship_certifications")
    end
  end

  def build_ysws_reviews
    projects.first(PROD[:ysws][:pending] + PROD[:ysws][:decided]).each_with_index do |project, i|
      ship = ship_event_for(project, created_at: ago, certification_status: "approved")
      created = ship.created_at + 1.hour
      review = Certification::Ysws.create!(post_ship_event: ship, project: project, user: owner_of(project),
                                           original_minutes: @random.rand(120..900), approved_minutes: @random.rand(60..800))

      if i < PROD[:ysws][:pending]
        review.update_columns(created_at: created, updated_at: created,
                              claimed_at: (created + 3.hours if @random.rand > PROD[:ysws][:unclaimed_rate]))
      else
        reviewed = created + latency(:ysws)
        approved = @random.rand < PROD[:ysws][:approve_rate]
        review.update_columns(created_at: created, updated_at: reviewed,
                              claimed_at: created + (reviewed - created) * 0.4,
                              reviewed_at: (reviewed if approved), returned_at: (reviewed unless approved))
      end
      track("ysws_reviews")
    end
  end

  def build_integrity_reviews
    Post::ShipEvent.where(id: Post.where(project_id: projects.map(&:id)).select(:postable_id)).limit(14).each_with_index do |ship, i|
      next if Certification::Integrity.exists?(ship_event_id: ship.id)

      created = ago(30)
      pending = i < PROD[:integrity][:pending]
      status = pending ? :pending : %i[manually_passed banned deducted].sample(random: @random)
      review = Certification::Integrity.new(ship_event_id: ship.id, status: status,
                                            reviewer: (users.first unless pending),
                                            deduction_minutes: (@random.rand(15..240) if status == :deducted))
      save_unvalidated!(review)
      review.update_columns(created_at: created, updated_at: created,
                            claimed_at: (created + 1.hour if pending && i.even?),
                            reviewed_at: (created + latency(:integrity) unless pending))
      track("integrity_reviews")
    end
  end

  def build_funding_requests
    # Must not overlap the payout-path pools below, or a fixed-prize project
    # picks up a hardware_stage and its journeys get relabelled.
    hardware_projects = projects[28, PROD[:funding][:pending] + PROD[:funding][:decided]] || []
    hardware_projects.each_with_index do |project, i|
      project.update_columns(hardware_stage: "design") if project.hardware_stage.blank?
      created = ago(45)
      pending = i < PROD[:funding][:pending]
      request = Certification::FundingRequest.new(
        project: project, user: owner_of(project), complexity_tier: 2,
        requested_amount_cents: (@random.rand(0.4..1.8) * 9_409).round,
        # Production returns far more funding requests than it approves.
        status: pending ? :pending : (@random.rand < PROD[:funding][:approve_rate] ? :approved : :returned)
      )
      save_unvalidated!(request,
                        created_at: created, updated_at: created,
                        claimed_at: (created + 4.hours if @random.rand > PROD[:funding][:unclaimed_rate]),
                        decided_at: (created + latency(:funding) unless pending))
      track("funding_requests")
    end
  end

  def build_mission_submissions
    mission = Mission.first
    return unless mission

    ships = Post::ShipEvent.where(id: Post.where(project_id: projects.map(&:id)).select(:postable_id)).limit(20).to_a
    ships.each_with_index do |ship, i|
      next if Mission::Submission.with_deleted.exists?(ship_event_id: ship.id)

      created = ship.created_at + 30.minutes
      pending = i < PROD[:mission][:pending]
      submission = Mission::Submission.new(
        mission: mission, ship_event_id: ship.id,
        payout_path: i.even? ? "voting" : "static_prize"
      )
      save_unvalidated!(submission)
      # AASM refuses direct assignment of its column, so the state is written
      # alongside the timestamps rather than through a transition.
      submission.update_columns(
        status: pending ? "pending" : (@random.rand < PROD[:mission][:approve_rate] ? "approved" : "rejected"),
        created_at: created, updated_at: created, pending_at: created,
        claimed_at: (created + 2.hours if pending && @random.rand > PROD[:mission][:unclaimed_rate]),
        reviewed_at: (created + latency(:mission) unless pending))
      track("mission_submissions")
    end
  end

  def build_shop
    items = PROD[:shop_items].keys.to_h { |type| [ type, "Seed #{type.demodulize.titleize}" ] }.map do |type, name|
      ShopItem.find_by(name: name) || begin
        item = ShopItem.new(type: type, name: name, ticket_cost: 25, enabled: true,
                            description: "#{TAG} sample item",
                            internal_description: "#{TAG} sample item")
        save_unvalidated!(item, created_at: ago(20))
        track("shop_items")
        item
      end
    end

    items_by_type = items.index_by(&:type)
    floors = %w[awaiting_periodical_fulfillment awaiting_periodical_fulfillment awaiting_periodical_fulfillment
                awaiting_periodical_fulfillment awaiting_periodical_fulfillment awaiting_periodical_fulfillment
                pending pending pending awaiting_verification awaiting_verification on_hold on_hold]

    60.times do |i|
      item = items_by_type[weighted(PROD[:shop_items])] || items.first
      owner = users[i % users.size]
      # Old enough that some warehouse orders trip the stale-fulfillment flag.
      created = floors[i] == "awaiting_periodical_fulfillment" ? ago(20) : ago(60)
      state = floors[i] || weighted(PROD[:order_states])
      awaiting_at = created + 8.hours
      stamps =
        case state
        when "on_hold" then { on_hold_at: created + 5.hours }
        when "rejected" then { rejected_at: created + @random.rand(2..40).hours }
        when "awaiting_periodical_fulfillment" then { awaiting_periodical_fulfillment_at: awaiting_at }
        when "fulfilled" then { awaiting_periodical_fulfillment_at: awaiting_at, fulfilled_at: awaiting_at + latency(:fulfillment) }
        else {}
        end
      next if stamps[:fulfilled_at] && stamps[:fulfilled_at] > @now

      order = ShopOrder.new(shop_item: item, user: owner, frozen_item_price: item.ticket_cost, quantity: 1)
      save_unvalidated!(order)
      order.update_columns(stamps.merge(aasm_state: state, created_at: created, updated_at: created))
      track("shop_orders")
    end
  end

  def build_reports
    24.times do |i|
      project = projects[i % projects.size]
      reporter = users[i % (users.size - 6)]
      created = ago(50)
      pending = i < 8
      report = Project::Report.create!(
        project: project, reporter: reporter,
        reason: weighted(PROD[:report_reasons]),
        details: "#{TAG} sample report",
        status: pending ? :pending : %i[reviewed dismissed].sample(random: @random)
      )
      report.update_columns(created_at: created, updated_at: pending ? created : created + @random.rand(2..70).hours)
      track("reports")
    end

    # The fraud queue filters on reason "fraud", and production currently has
    # none of those at all, so open ones are forced here or the panel is blank.
    projects.last(5).each_with_index do |project, i|
      report = Project::Report.create!(project: project, reporter: users[i + 1], reason: "fraud",
                                       details: "#{TAG} sample fraud report")
      report.update_columns(created_at: ago(20), status: 0)
      track("reports")
    end
  end

  # Ships that made it all the way to payout, which is what the waterfall
  # measures, plus the votes and flags behind them.
  def build_votes_and_payouts
    voters = users.last(20)

    # Disjoint project pools per path: `path_for` keys off the project's
    # hardware_stage, so a project shared between paths would mislabel both.
    pools = {
      "voting" => projects[0, 12] || [],
      "hardware" => projects[28, 8] || [],
      "static_prize" => projects[16, 8] || []
    }

    pools.flat_map { |path, pool| pool.map { |project| [ path, project ] } }.each_with_index do |(path, project), i|
      cert_span = latency(:ship_cert)
      rating_span = path == "voting" ? latency(:rating) : 0.seconds
      payout_span = latency(:payout)
      total = cert_span + rating_span + payout_span
      # Finish somewhere in the last 25 days so the 7 and 30 day views both
      # have journeys to measure.
      paid = @now - (@random.rand * 25).days
      shipped = paid - total
      voting_started = shipped + cert_span
      voting_completed = voting_started + rating_span
      next if path != "hardware" && project.hardware_stage.present?

      project.update_columns(hardware_stage: "build") if path == "hardware"

      attributes = {
        certification_status: "approved",
        lifecycle_data_quality: @random.rand < 0.8 ? "live" : "backfilled_exact",
        payout: @random.rand(50..400)
      }
      attributes.merge!(voting_started_at: voting_started, voting_completed_at: voting_completed) if path == "voting"
      ship = ship_event_for(project, created_at: shipped, **attributes.merge(paid_at: paid))
      track("paid_ships")

      cert = Certification::Ship.create!(project: project, post_ship_event_id: ship.id, status: :approved)
      cert.update_columns(created_at: shipped, claimed_at: shipped + 3.hours,
                          decided_at: shipped + @random.rand(5..48).hours, updated_at: shipped)

      # The waterfall reads a ship's path off its mission submission, so a
      # fixed-prize journey only exists if the submission says so.
      if path == "static_prize" && (mission = Mission.first)
        submission = Mission::Submission.new(mission: mission, ship_event_id: ship.id, payout_path: "static_prize")
        save_unvalidated!(submission)
        submission.update_columns(status: "approved", created_at: shipped + 30.minutes,
                                  pending_at: shipped + 30.minutes,
                                  reviewed_at: shipped + @random.rand(4..60).hours,
                                  claimed_at: shipped + 2.hours, updated_at: shipped)
        track("mission_submissions")
      end

      next unless path == "voting"

      voters.reject { |voter| voter.id == owner_of(project).id }.first(@random.rand(6..14)).each_with_index do |voter, v|
        voted_at = voting_started + (v * 3).hours
        next if voted_at > @now

        vote = Vote.create!(
          user: voter, project: project, ship_event_id: ship.id,
          originality_score: score_near(PROD[:vote][:scores][:originality]),
          technical_score: score_near(PROD[:vote][:scores][:technical]),
          usability_score: score_near(PROD[:vote][:scores][:usability]),
          storytelling_score: score_near(PROD[:vote][:scores][:storytelling]),
          time_taken_to_vote_in_seconds: latency_hours(*PROD[:vote][:seconds]).round,
          repo_opened: @random.rand < PROD[:vote][:repo_rate],
          demo_opened: @random.rand < PROD[:vote][:demo_rate],
          discarded: @random.rand < PROD[:vote][:discarded_rate],
          reason: sample_vote_reason
        )
        vote.update_columns(created_at: voted_at, updated_at: voted_at)
        track("votes")

        assignment = Vote::Assignment.create!(
          user: voter, ship_event_id: ship.id, status: "submitted", vote_id: vote.id, view_count: @random.rand(1..4)
        )
        assignment.update_columns(created_at: voted_at - 20.minutes, first_viewed_at: voted_at - 15.minutes,
                                  submitted_at: voted_at, updated_at: voted_at)
        track("vote_assignments")

        next unless v.zero? && i % 4 == 0

        flag = Vote::Event.create!(user: voter, vote_id: vote.id, ship_event_id: ship.id, project: project,
                                   event_type: "vote_flagged", occurred_at: voted_at + 1.hour)
        flag.update_columns(created_at: voted_at + 1.hour, updated_at: voted_at + 1.hour)
        track("vote_flags")

        next unless i % 8 == 0

        resolution = Vote::Event.create!(user: voter, vote_id: vote.id, ship_event_id: ship.id, project: project,
                                         event_type: "vote_flag_rejected", occurred_at: voted_at + 20.hours)
        resolution.update_columns(created_at: voted_at + 20.hours, updated_at: voted_at + 20.hours)
      end

      entry = LedgerEntry.create!(user: owner_of(project), ledgerable: ship, amount: ship.payout, reason: "#{TAG} payout")
      entry.update_columns(created_at: paid, updated_at: paid)
      track("ledger_entries")
    end

    # Some spend, so utilization isn't a flat 0%.
    users.first(12).each_with_index do |user, i|
      ship = Post::ShipEvent.where(id: Post.where(project_id: projects.map(&:id)).select(:postable_id)).first
      next unless ship

      created = ago(30)
      spend = [ (LedgerEntry.where("amount > 0").sum(:amount) * 0.06).round, 5 ].max
      entry = LedgerEntry.create!(user: user, ledgerable: ship, amount: -@random.rand(5..spend), reason: "#{TAG} spend #{i}")
      entry.update_columns(created_at: created, updated_at: created)
      track("ledger_entries")
    end

    # Unpaid ships sitting in the payout review queue.
    6.times do |i|
      project = projects[(i + 5) % projects.size]
      shipped = ago(15)
      completed = shipped + 20.hours
      ship = ship_event_for(project, created_at: shipped, certification_status: "approved",
                            lifecycle_data_quality: "live",
                            voting_started_at: shipped + 2.hours, voting_completed_at: completed)
      voters.reject { |voter| voter.id == owner_of(project).id }.first(13).each_with_index do |voter, v|
        next if Vote.exists?(user_id: voter.id, ship_event_id: ship.id)

        vote = Vote.create!(user: voter, project: project, ship_event_id: ship.id,
                            originality_score: score_near(PROD[:vote][:scores][:originality]),
                            technical_score: score_near(PROD[:vote][:scores][:technical]),
                            usability_score: score_near(PROD[:vote][:scores][:usability]),
                            storytelling_score: score_near(PROD[:vote][:scores][:storytelling]),
                            reason: sample_vote_reason,
                            repo_opened: @random.rand < PROD[:vote][:repo_rate],
                            demo_opened: @random.rand < PROD[:vote][:demo_rate],
                            time_taken_to_vote_in_seconds: latency_hours(*PROD[:vote][:seconds]).round)
        vote.update_columns(created_at: completed - (v + 1).hours, updated_at: completed)
        track("votes")
      end
      voters.last(14).each_with_index do |voter, v|
        next if Vote::Assignment.exists?(user_id: voter.id, ship_event_id: ship.id)

        status = weighted(PROD[:assignment_mix].except("submitted"))
        assigned_at = completed - (v + 2).hours
        assignment = Vote::Assignment.new(user: voter, ship_event_id: ship.id, view_count: v % 3)
        save_unvalidated!(assignment)
        assignment.update_columns(
          status: status, created_at: assigned_at, updated_at: assigned_at,
          first_viewed_at: (assigned_at + 5.minutes unless v.zero?),
          skipped_at: (assigned_at + 10.minutes if status == "skipped")
        )
        track("vote_assignments")
      end

      track("payout_review_ships")
    end
  end

  # `voteable` needs an approved, unpaid ship with hours logged, both project
  # links present, and no fixed-prize submission. Without these the vote panel's
  # headline "votes needed to clear" is permanently zero.
  def build_voting_pool
    voters = users.last(20)

    10.times do |i|
      project = projects[i]
      next if project.hardware_stage.present?

      shipped = ago(12)
      ship = ship_event_for(project, created_at: shipped, certification_status: "approved",
                            lifecycle_data_quality: "live", hours_at_ship: @random.rand(5.0..40.0).round(1),
                            voting_started_at: shipped + 3.hours)

      # Deliberately short of the threshold, so the queue has real work left.
      @random.rand(2..10).times do |v|
        voter = voters[(i + v) % voters.size]
        next if voter.id == owner_of(project).id
        next if Vote.exists?(user_id: voter.id, ship_event_id: ship.id)

        voted_at = shipped + (4 + v * 6).hours
        next if voted_at > @now

        vote = Vote.create!(user: voter, project: project, ship_event_id: ship.id,
                            originality_score: score_near(PROD[:vote][:scores][:originality]),
                            technical_score: score_near(PROD[:vote][:scores][:technical]),
                            usability_score: score_near(PROD[:vote][:scores][:usability]),
                            storytelling_score: score_near(PROD[:vote][:scores][:storytelling]),
                            reason: sample_vote_reason,
                            time_taken_to_vote_in_seconds: latency_hours(*PROD[:vote][:seconds]).round)
        vote.update_columns(created_at: voted_at, updated_at: voted_at)
        track("votes")

        # Production has 146 flags against 145 resolutions, so most are settled
        # and a couple are always open.
        next unless v.zero? && i < 6

        flag = Vote::Event.create!(user: voter, vote_id: vote.id, ship_event_id: ship.id, project: project,
                                   event_type: "vote_flagged", occurred_at: voted_at + 2.hours)
        flag.update_columns(created_at: voted_at + 2.hours, updated_at: voted_at + 2.hours)
        track("vote_flags")

        next if i < 2

        resolved = Vote::Event.create!(user: voter, vote_id: vote.id, ship_event_id: ship.id, project: project,
                                       event_type: %w[vote_flag_accepted vote_flag_rejected].sample(random: @random),
                                       occurred_at: voted_at + 30.hours)
        resolved.update_columns(created_at: voted_at + 30.hours, updated_at: voted_at + 30.hours)
      end

      track("voteable_ships")
    end
  end

  def build_certificates
    users.each_with_index do |user, i|
      next if Certificate.exists?(user_id: user.id)
      break if i >= PROD[:certificate][:pending] + PROD[:certificate][:decided]

      created = ago(40)
      certificate = Certificate.create!(
        user: user, name: "Seed Tester #{i}", hours_at_issue: @random.rand(20..90),
        status: i < PROD[:certificate][:pending] ? "pending" : %w[approved rejected].sample(random: @random)
      )
      certificate.update_columns(created_at: created,
                                 updated_at: i < PROD[:certificate][:pending] ? created : created + @random.rand(2..60).hours)
      track("certificates")
    end
  end

  # The fraud panel reads ban history off PaperTrail rather than a table, so
  # the versions are what has to exist.
  def build_bans
    # Scaled up from the production rate so the trend chart has more than a
    # single bar at dev size, while the standing banned share stays close to it.
    # Enough to leave a standing banned population after the unbans below.
    users.first(12).each_with_index do |user, i|
      banned_at = ago(25)
      PaperTrail::Version.create!(
        item_type: "User", item_id: user.id, event: "update", whodunnit: users.first.id.to_s,
        object_changes: { "banned" => [ false, true ] }, created_at: banned_at
      )
      track("ban_versions")

      if i < 5
        PaperTrail::Version.create!(
          item_type: "User", item_id: user.id, event: "update", whodunnit: users.first.id.to_s,
          object_changes: { "banned" => [ true, false ] }, created_at: banned_at + 3.days
        )
        track("ban_versions")
      else
        user.update_columns(banned: true, banned_at: banned_at)
      end
    end
  end

  # Jelly's own history only starts when the sync first ran, so backfill the
  # days before that to give the charts a shape. Today's real row is left alone.
  def build_jelly_history
    open_count = JellyConversation.open_now.count
    (1..DAYS).each do |days_ago|
      date = @now.to_date - days_ago
      next if JellyDailyStat.exists?(recorded_on: date)

      JellyDailyStat.create!(
        recorded_on: date,
        open_count: [ open_count + @random.rand(-8..12), 0 ].max,
        awaiting_reply_count: [ open_count + @random.rand(-10..8), 0 ].max,
        arrivals: @random.rand(8..45),
        resolutions: @random.rand(8..45),
        median_first_response_seconds: @random.rand(1..30) * 3600,
        p95_hang_seconds: @random.rand(6..72) * 3600
      )
      track("jelly_daily_stats")
    end
  end
end
