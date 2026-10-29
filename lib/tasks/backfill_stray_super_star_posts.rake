# Before #1506, unmarking a project as Super Star left its announcement post in
# the feed, and marking it again added a second one. #1506 fixed it going
# forward; this removes the announcements left behind: every Super Star post on
# a project that isn't a Super Star any more, and all but the newest on one
# that is.
#
# dry run:  bin/rails backfill:stray_super_star_posts
# to apply: bin/rails backfill:stray_super_star_posts DRY_RUN=false

namespace :backfill do
  desc "Delete Super Star posts left behind by unmarking (and re-marking) projects"
  task stray_super_star_posts: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    puts dry_run ? "[DRY RUN] No changes will be written." : "Writing changes to the database."
    puts

    count = 0

    Post.of_fire_events.preload(:postable).order(:created_at).group_by(&:project_id).each do |project_id, posts|
      project = Project.with_deleted.find_by(id: project_id)
      stray = project&.fire? ? posts[0...-1] : posts

      stray.each do |post|
        reason = project&.fire? ? "older duplicate" : "project isn't a Super Star"
        puts "  [DELETE] Post ##{post.id} on project ##{project_id} \"#{project&.title}\" (#{post.created_at.to_date}), #{reason}"

        post.postable.destroy! unless dry_run

        count += 1
      end
    end

    puts
    puts "#{dry_run ? 'Would delete' : 'Deleted'} #{count} post(s)."
    puts "Run with DRY_RUN=false to apply." if dry_run
  end
end
