require_relative "config"
require_relative "helpers"
require_relative "users"
require_relative "projects"
require_relative "devlogs"
require_relative "comments"
require_relative "likes"
require_relative "follows"
require_relative "reposts"
require_relative "stardust"
require_relative "summary"

module DevelopmentSeed
  class Runner
    include Helpers
    extend Helpers

    def self.call
      new.call
    end

    def call
      log "Starting development community seed..."

      cleanup

      users = DevelopmentSeed::Users.call
      projects = DevelopmentSeed::Projects.call(users)
      posts = DevelopmentSeed::Devlogs.call(projects)

      DevelopmentSeed::Comments.call(users, posts)
      DevelopmentSeed::Likes.call(users, posts)
      DevelopmentSeed::Follows.call(users, projects)
      DevelopmentSeed::Reposts.call(users, posts)
      DevelopmentSeed::Stardust.call(users)

      DevelopmentSeed::Summary.call
      log "Development community seed complete!"
    end

    def cleanup
      progress "Cleaning up existing community data"

      # Protect the admin user and their projects
      admin = User.find_by(email: "kartikey@hackclub.com")
      admin_id = admin&.id
      admin_project_ids = admin&.memberships&.pluck(:project_id) || []

      # 0. Kill LedgerEntries first
      LedgerEntry.where.not(user_id: admin_id).delete_all

      # 1. Kill Reposts first (they reference both Posts and Users)

      Post::Repost.unscoped.destroy_all

      # 2. Kill all Postables (Devlog, ShipEvent, etc.)
      Postable.types.each do |type|
        klass = type.constantize
        next if klass == Post::Repost

        query = klass.respond_to?(:unscoped) ? klass.unscoped : klass

        query.joins(:post).where.not(posts: { project_id: admin_project_ids })
             .or(query.joins(:post).where.not(posts: { user_id: admin_id }))
             .destroy_all
      end

      # 3. Kill any remaining orphan Posts
      Post.unscoped.where.not(project_id: admin_project_ids)
          .or(Post.unscoped.where.not(user_id: admin_id))
          .destroy_all

      # 4. Kill community Projects
      Project.unscoped.where.not(id: admin_project_ids).destroy_all

      # 5. Kill community Users
      User.where.not(email: "kartikey@hackclub.com").destroy_all

      done
    end
  end
end
