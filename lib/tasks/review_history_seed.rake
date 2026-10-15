# Development-only sample data for the review-history panel on the two review
# pages. The panel only has something to show once a project has been rejected
# and re-shipped, which normal dev data never has, so this builds demo projects
# at a range of depths. Everything is tagged with TAG so `review_history:unseed`
# removes exactly what this added and nothing else.
namespace :review_history do
  desc "Create projects with varying numbers of returned-and-re-reviewed mission reviews"
  task seed: :environment do
    abort "Refusing to seed outside development." unless Rails.env.development?

    seeder = ReviewHistorySeeder.new
    seeder.run
    puts seeder.report
  end

  desc "Remove everything review_history:seed created"
  task unseed: :environment do
    abort "Refusing to unseed outside development." unless Rails.env.development?

    puts ReviewHistorySeeder.new.destroy_all
  end
end

class ReviewHistorySeeder
  TAG = "review-history-seed".freeze
  DOMAIN = "reviewhistory.seed".freeze
  SLACK_PREFIX = "UREVHIST".freeze
  MISSION_SLUG = "review-history-demo".freeze

  # Rejected-and-re-shipped rounds sitting behind each software project's
  # pending review. Zero is included so the empty state is on screen too.
  DEPTHS = [ 0, 1, 2, 3, 5 ].freeze

  REJECTIONS = [
    "README is a stub. Say what it does and how to run it, then re-ship.",
    "The demo link 404s for me. Re-ship once it is public.",
    "Hackatime shows 40 minutes against a 10 hour claim.",
    "This is the tutorial project unchanged. Make it yours.",
    "No screenshots, and the repo has a single commit."
  ].freeze

  REVIEWERS = %w[nova quill pixel].freeze

  def initialize(now: Time.current)
    @now = now
    @counts = Hash.new(0)
  end

  def run
    ActiveRecord::Base.transaction do
      build_reviewers
      build_builders
      build_software_projects
    end
    self
  end

  def report
    lines = [ "Seeded:" ] + @counts.sort.map { |name, count| format("  %-28s %s", name, count) }
    lines += [ "", "Review queue: /admin/missions/#{MISSION_SLUG}/submissions" ]
    lines.join("\n")
  end

  def destroy_all
    removed = Hash.new(0)
    ActiveRecord::Base.transaction do
      users = User.where("email LIKE ?", "%@#{DOMAIN}")
      projects = Project.where("projects.description LIKE ?", "%#{TAG}%")
      ships = Post::ShipEvent.where(id: Post.where(project_id: projects.select(:id)).select(:postable_id))
      devlogs = Post::Devlog.where(id: Post.where(project_id: projects.select(:id)).select(:postable_id))

      removed["mission_submissions"] = Mission::Submission.with_deleted.where(ship_event_id: ships.select(:id)).delete_all
      removed["ship_certifications"] = Certification::Ship.where(project_id: projects.select(:id)).delete_all
      removed["funding_requests"] = Certification::FundingRequest.where(project_id: projects.select(:id)).delete_all
      removed["mission_attachments"] = Project::MissionAttachment.where(project_id: projects.select(:id)).delete_all
      removed["memberships"] = Project::Membership.where(project_id: projects.select(:id)).delete_all
      # Opening a demo project's page records a view, which holds a foreign key
      # back to the post and blocks the delete below.
      removed["post_views"] = PostView.where(post_id: Post.where(project_id: projects.select(:id)).select(:id)).delete_all
      removed["posts"] = Post.where(project_id: projects.select(:id)).delete_all
      removed["ship_events"] = Post::ShipEvent.where(id: ships.select(:id)).delete_all
      removed["devlogs"] = Post::Devlog.where(id: devlogs.select(:id)).delete_all
      removed["projects"] = projects.destroy_all.size
      removed["missions"] = Mission.with_deleted.where(slug: mission_slugs).destroy_all.size
      # destroy_all rather than delete_all: creating a user spins up dependent
      # records that hold foreign keys back to it.
      removed["users"] = users.destroy_all.size
    end

    ([ "Removed:" ] + removed.sort.map { |name, count| format("  %-28s %s", name, count) }).join("\n")
  end

  private

  def track(name, count = 1) = @counts[name] += count

  def mission_slugs = [ MISSION_SLUG, "#{MISSION_SLUG}-earlier" ]

  def save_unvalidated!(record, **columns)
    record.save!(validate: false)
    record.update_columns(columns) if columns.any?
    record
  end

  def build_reviewers
    @reviewers = REVIEWERS.each_with_index.map do |name, i|
      User.find_by(email: "reviewer-#{name}@#{DOMAIN}") || begin
        track("reviewers")
        User.create!(slack_id: "#{SLACK_PREFIX}R#{i}", display_name: "seed_reviewer_#{name}",
                     email: "reviewer-#{name}@#{DOMAIN}", granted_roles: [ "mission_reviewer" ])
      end
    end
  end

  def build_builders
    @builders = DEPTHS.size.times.map do |i|
      User.find_by(email: "builder-#{i}@#{DOMAIN}") || begin
        track("builders")
        User.create!(slack_id: "#{SLACK_PREFIX}B#{i}", display_name: "seed_builder_#{i}",
                     email: "builder-#{i}@#{DOMAIN}")
      end
    end
  end

  # The mission whose queue the pending reviews land in, plus an older one so
  # the deepest project shows history spanning more than a single mission.
  def mission
    @mission ||= find_or_create_mission(MISSION_SLUG, "Review History Demo")
  end

  def earlier_mission
    @earlier_mission ||= find_or_create_mission("#{MISSION_SLUG}-earlier", "Review History Demo (earlier)")
  end

  def find_or_create_mission(slug, name)
    Mission.find_by(slug: slug) || begin
      track("missions")
      Mission.create!(slug: slug, name: name, enabled: true,
                      description: "#{TAG} demo mission",
                      submission_guide: "Check the README, the demo link, and the logged hours.")
    end
  end

  def build_software_projects
    DEPTHS.each_with_index do |depth, i|
      owner = @builders[i]
      project = create_project("Review History Demo #{depth} #{'round'.pluralize(depth)}", owner)
      project.mission_attachments.create!(mission: mission)

      # The deepest project also carries a verdict from a different mission, so
      # the panel shows cross-mission context and not just one re-review loop.
      decide!(project, owner, earlier_mission, status: "approved", at: @now - (depth + 4).weeks) if depth >= 5

      # The last rejection is the one still on the row; asking for a re-review
      # puts it back in the queue with its verdict wiped, which is the state a
      # reviewer actually opens.
      submission = reject_rounds!(project, owner, depth)
      if submission
        request_re_review!(submission, at: @now - 2.days)
      else
        pending_submission!(project, owner)
      end
      track("software_projects")
    end
  end

  def create_project(title, owner)
    project = Project.create!(title: title,
                              description: "#{TAG} sample project",
                              readme_url: "https://example.test/readme",
                              demo_url: "https://example.test/demo",
                              repo_url: "https://example.test/repo")
    Project::Membership.create!(project: project, user: owner, role: :owner)
    track("projects")
    project
  end

  # The real loop: a builder hitting "request re-review" reuses the same ship
  # event and submission, and Projects::MissionResubmissionsController clears the
  # verdict off the row before sending it back to pending. So rounds after the
  # first mutate one submission in place, leaving their evidence only in
  # PaperTrail, exactly as production does.
  def reject_rounds!(project, owner, depth)
    return if depth.zero?

    submission = new_submission(project, owner, mission, @now - (depth * 6).days)
    depth.times do |round|
      at = @now - ((depth - round) * 6).days
      reject!(submission, at: at, feedback: REJECTIONS[round % REJECTIONS.size])
      # Every round but the last is re-reviewed, which wipes the verdict.
      request_re_review!(submission, at: at + 1.day) unless round == depth - 1
    end
    submission
  end

  def reject!(submission, at:, feedback:)
    submission.update!(reviewed_by: next_reviewer, reviewed_at: at, rejection_message: feedback)
    submission.update_columns(status: "rejected", updated_at: at)
    track("rejections")
    submission
  end

  # Mirrors the controller: clear the verdict, then send the row back to pending.
  # Two separate writes, because the version that clears the verdict is the one
  # the review page reads it back out of.
  def request_re_review!(submission, at:)
    submission.update!(reviewed_by: nil, reviewed_at: nil, rejection_message: nil,
                       claimed_at: nil, claim_expires_at: nil)
    submission.update_columns(status: "pending", pending_at: at, updated_at: at)
    track("re_review_requests")
    submission
  end

  def next_reviewer
    @reviewer_cursor = (@reviewer_cursor || -1) + 1
    @reviewers[@reviewer_cursor % @reviewers.size]
  end

  def decide!(project, owner, target_mission, status:, at:, feedback: nil)
    submission = new_submission(project, owner, target_mission, at)
    # AASM refuses direct assignment of its column, so the verdict is written
    # alongside its timestamps rather than through a transition.
    submission.update_columns(status: status, pending_at: at, reviewed_at: at + 2.days,
                              reviewed_by_id: @reviewers[@counts["decided_reviews"] % @reviewers.size].id,
                              rejection_message: feedback, updated_at: at + 2.days)
    track("decided_reviews")
    submission
  end

  def pending_submission!(project, owner)
    at = @now - 2.days
    submission = new_submission(project, owner, mission, at)
    submission.update_columns(status: "pending", pending_at: at, updated_at: at)
    track("pending_reviews")
    submission
  end

  def new_submission(project, owner, target_mission, at)
    ship = ship_event_for(project, owner, at)
    submission = Mission::Submission.new(ship_event: ship, mission: target_mission, payout_path: "voting")
    save_unvalidated!(submission, created_at: at, updated_at: at)
  end

  # A ship event plus the Post that hangs it off the project. Timestamps are
  # written straight to columns so callbacks can't stamp them back to now.
  def ship_event_for(project, owner, created_at)
    ship = Post::ShipEvent.create!(body: "#{TAG} ship", uploading_attachments: true)
    Post.create!(project: project, user: owner, postable: ship, created_at: created_at)
    ship.update_columns(created_at: created_at, updated_at: created_at)
    track("ship_events")
    ship.reload
  end
end
