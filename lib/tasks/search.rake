# frozen_string_literal: true

namespace :search do
  desc "Rebuild the Redis semantic search index"
  task reindex: :environment do
    abort "SEARCH_REDIS_URL is required" if SemanticSearch.redis_url.blank?
    abort "OPENAI_API_KEY or credentials.openai.api_key is required" if SemanticSearch.openai_api_key.blank?

    redis = SemanticSearch.redis

    begin
      redis.call("FT.DROPINDEX", SemanticSearch::INDEX_NAME, "DD")
    rescue Redis::CommandError => e
      raise unless e.message.match?(/Unknown Index name|no such index/i)
    end

    SemanticSearch.ensure_index!

    indexed = Hash.new(0)

    Project.not_deleted.find_in_batches do |batch|
      indexed["project"] += SemanticSearch.upsert_batch(batch)
      print "."
    end

    Post.of_devlogs(join: true)
        .where(post_devlogs: { deleted_at: nil })
        .includes(:postable, :project, :user)
        .find_in_batches do |batch|
      records = batch.filter_map(&:postable)
      indexed["devlog"] += SemanticSearch.upsert_batch(records)
      print "."
    end

    Post.of_ship_events(join: true)
        .where.not(post_ship_events: { certification_status: "rejected" })
        .includes(:postable, :project, :user)
        .find_in_batches do |batch|
      records = batch.filter_map(&:postable)
      indexed["ship"] += SemanticSearch.upsert_batch(records)
      print "."
    end

    User.discoverable.where.not(display_name: [ nil, "" ]).find_in_batches do |batch|
      indexed["user"] += SemanticSearch.upsert_batch(batch)
      print "."
    end

    puts ""
    puts "Indexed #{indexed.sort.map { |type, count| "#{count} #{type}" }.join(', ')}"
  end

  desc "Create development records for exercising search UI"
  task seed_dev: :environment do
    abort "search:seed_dev is only for development" unless Rails.env.development?

    users = [
      [ "jenna_stardance", "Jenna is exploring constellation choreography and tiny Rails tools.", %w[art_design web_dev] ],
      [ "ronald_prasad", "Ronald ships hardware dashboards for cosmic dance parties.", %w[hardware web_dev] ],
      [ "gd4378", "GD4378 builds animation experiments with stars, sprites, and music.", %w[game_dev art_design] ],
      [ "stardance_saf", "Stardance Animation Festival collects devlogs about motion and storytelling.", %w[art_design] ],
      [ "daily_stardancer", "Daily Stardancer archives project updates and devlog highlights.", %w[web_dev] ]
    ].map do |display_name, bio, interests|
      User.find_or_initialize_by(display_name: display_name).tap do |user|
        user.email ||= "#{display_name}@example.test"
        user.slack_id ||= "U_SEARCH_#{display_name.upcase.gsub(/[^A-Z0-9]/, '_')}"
        user.bio = bio
        user.interests = interests
        user.verification_status = "verified"
        user.save!

        User::Identity.find_or_create_by!(user: user, provider: "hack_club") do |identity|
          identity.uid = "search-dev-#{display_name}"
          identity.access_token = "search-dev-token"
        end
      end
    end

    projects = [
      [ "Stardance Mobile", "A mobile app for tracking practice sessions, music cues, and stardust rewards." ],
      [ "Stardance Utils", "Tiny Ruby utilities for parsing devlog content and surfacing semantic search examples." ],
      [ "stardisco", "A multiplayer disco floor rendered with CSS grids and constellation color palettes." ],
      [ "StarCLI", "A command line tool for logging devlog progress from the terminal." ],
      [ "Exterstellar", "An interstellar project gallery with semantic search and cozy profile pages." ]
    ].map.with_index do |(title, description), index|
      Project.find_or_create_by!(title: title) do |project|
        project.description = description
        project.ship_status = "draft"
      end.tap do |project|
        Project::Membership.find_or_create_by!(project: project, user: users[index % users.length]) do |membership|
          membership.role = :owner
        end
      end
    end

    devlog_bodies = [
      "Implemented fuzzy constellation matching for dance move names and tuned the search result panel.",
      "Added Redis-backed semantic lookup for devlog content, project summaries, and stardancer profiles.",
      "Recorded a prototype animation loop where orbiting stars react to music beats.",
      "Built the first terminal command that posts a devlog after a coding session.",
      "Designed a profile search row with avatars, handles, and compact metadata."
    ]

    projects.each_with_index do |project, index|
      author = project.memberships.find_by(role: :owner)&.user || users.first
      devlog = Post::Devlog.where(body: devlog_bodies[index]).first_or_initialize
      devlog.uploading_attachments = true
      devlog.duration_seconds ||= 45.minutes.to_i
      devlog.save!

      Post.find_or_create_by!(project: project, user: author, postable: devlog)

      ship = Post::ShipEvent.where(body: "Shipped #{project.title} with a searchable demo and devlog trail.").first_or_create!
      Post.find_or_create_by!(project: project, user: author, postable: ship)
    end

    if SemanticSearch.enabled?
      (users + projects).each { |record| SemanticSearch.upsert(record) }
      Post.of_devlogs.includes(:postable).find_each { |post| SemanticSearch.upsert(post.postable) if post.postable }
      Post.of_ship_events.includes(:postable).find_each { |post| SemanticSearch.upsert(post.postable) if post.postable }
      puts "Seeded and indexed search development records."
    else
      puts "Seeded search development records. Configure SEARCH_REDIS_URL and OPENAI_API_KEY, then run bin/rails search:reindex."
    end
  end
end
