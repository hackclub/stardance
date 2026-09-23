# frozen_string_literal: true

module DevelopmentSeed
  # Additive, repeatable UI data. No ships, certifications, payouts, or cleanup.
  class DemoFeed
    PEOPLE = %w[nova orbit lyra comet astro pixel luna cosmo vega sol echo quasar].freeze
    PROJECTS = [
      "Orbit Notes", "Star Map", "Moonbase Radio", "Comet Courier",
      "Asteroid Arcade", "Pixel Planet", "Lunar Garden", "Cosmic Clock",
      "Rocket Dashboard", "Solar Sketchbook", "Echo Terminal", "Quasar Quest"
    ].freeze
    UPDATES = [
      "the first prototype is alive! the main screen is in place, and keyboard navigation is finally working. next up: saving everything between sessions.",
      "today's progress: a new theme picker, better empty states, and a bunch of small accessibility fixes. the layout now behaves on my phone too.",
      "tracked down a sneaky rendering bug and added regression tests. i also cleaned up the settings screen — fewer clicks, much less confusion.",
      "polish day! added smooth transitions, clearer error messages, and a tiny celebration when you finish a task. looking for feedback on the flow."
    ].freeze
    ARTWORK = %w[
      landing/how-this-works/nebula-bg.png
      rocket_progress/wrench-buddy.png
      landing/how-this-works/card-star.png
      landing/how-this-works/card-left-bg.png
    ].freeze
    COMMENTS = [
      "love the space theme! how does it feel on a smaller screen?",
      "nice progress — the keyboard controls are a great touch.",
      "the new layout is much easier to follow. excited for the next update!"
    ].freeze

    def self.call = new.call

    def call
      raise "Demo feed is development-only" unless Rails.env.development?
      unless ActiveRecord::Base.connection_db_config.host.in?(%w[db localhost 127.0.0.1])
        raise "Demo feed requires a local database"
      end
      unless ActiveStorage::Blob.service.is_a?(ActiveStorage::Service::DiskService)
        raise "Demo feed requires local disk storage"
      end

      @now = Time.current
      # Keep all callback jobs in this one-off process; never deliver email,
      # Slack messages, analytics, recommendation syncs, or external indexing.
      original_base_adapter = ActiveJob::Base.queue_adapter
      original_app_adapter = ApplicationJob.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      ApplicationJob.queue_adapter = :test
      users = []
      posts = []
      ActiveRecord::Base.transaction do
        users = PEOPLE.map { |name| demo_user(name) }
        users.each_with_index do |user, index|
          project = user.projects.find_or_create_by!(title: "[demo] #{PROJECTS[index]}") do |record|
            record.description = "Local demo project for testing the Stardance feed. No real shipped hours or rewards."
            record.project_type = "Web App"
            record.created_at = @now - 7.days
          end
          project.memberships.find_or_create_by!(user: user) { |membership| membership.role = :owner }

          UPDATES.each_with_index do |update, sequence|
            body = "#{update}\n\nlocal demo · #{PROJECTS[index].downcase} · update #{sequence + 1}"
            post = project.posts.joins(:devlog).find_by(user: user, post_devlogs: { body: body })
            path = Rails.root.join("app/assets/images", ARTWORK[(index + sequence) % ARTWORK.size])
            if post
              attach_artwork(post.postable, path)
            else
              created_at = @now - (index * UPDATES.length + UPDATES.length - sequence).hours
              devlog = Post::Devlog.new(body: body, duration_seconds: (30 + index * 5 + sequence * 15).minutes,
                                        created_at: created_at, updated_at: created_at)
              attach_artwork(devlog, path)
              devlog.save!
              post = Post.create!(user: user, project: project, postable: devlog, created_at: created_at, updated_at: created_at)
            end
            posts << post
          end
        end

        posts.each_with_index do |post, index|
          peers = users.reject { |user| user.id == post.user_id }.rotate(index % (users.size - 1))
          peers.first(3 + index % 5).each do |peer|
            Like.find_or_create_by!(user: peer, likeable: post.postable)
          end
          peers.first(2).each_with_index do |peer, offset|
            Comment.find_or_create_by!(user: peer, commentable: post.postable,
                                       body: "#{COMMENTS[(index + offset) % COMMENTS.size]} (local demo)")
          end
        end
      end

      { users: users.size, projects: users.sum { |user| user.projects.count }, posts: posts.size,
        comments: Comment.where(user: users).count, likes: Like.where(user: users).count }
    ensure
      ActiveJob::Base.queue_adapter = original_base_adapter if original_base_adapter
      ApplicationJob.queue_adapter = original_app_adapter if original_app_adapter
    end

    private
      def attach_artwork(devlog, path)
        if (attachment = devlog.attachments.first)
          # Recover a previous interrupted upload without duplicating the post.
          unless attachment.blob.service.exist?(attachment.blob.key)
            File.open(path) { |file| attachment.blob.upload(file) }
          end
        else
          # Upload runs after the outer transaction commits, so keep the IO open.
          devlog.attachments.attach(io: StringIO.new(File.binread(path)), filename: path.basename.to_s, content_type: "image/png")
        end
      end

      def demo_user(name)
        User.find_or_create_by!(email: "#{name}@stardance-demo.invalid") do |user|
          user.display_name = "demo_#{name}"
          user.first_name = name.capitalize
          user.last_name = "Demo"
          user.bio = "Fictional local demo account for previewing Stardance. Not a real participant."
          user.verification_status = "verified"
          user.onboarded_at = @now - 7.days
          user.synced_at = @now
          user.created_at = @now - 7.days
          user.things_dismissed = %w[home_intro bukux2_intro bukux3_intro bukux3_role_reveal]
        end
      end
  end
end
