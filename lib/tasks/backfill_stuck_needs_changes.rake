# Before #683, Project#return_for_changes only allowed the under_review -> needs_changes
# transition. A project that was approved, then later returned by YSWS and
# sent back by Shipwrights on the same ship event, couldn't make that
# transition from :approved, so it got stuck showing an unclickable
# "Changes requested" badge forever. #683 fixed the transition going
# forward; this repairs projects that got stuck before it merged.
#
# dry run:  bin/rails backfill:stuck_needs_changes
# to apply: bin/rails backfill:stuck_needs_changes DRY_RUN=false

namespace :backfill do
  desc "Move projects stuck on 'approved' with a returned ship event into 'needs_changes'"
  task stuck_needs_changes: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    puts dry_run ? "[DRY RUN] No changes will be written." : "Writing changes to the database."
    puts

    count = 0

    Project.where(ship_status: "approved").find_each do |project|
      ship_event = project.last_ship_event

      next unless ship_event&.certification_status == "returned"

      unless project.may_return_for_changes?
        puts "  [SKIP] Project ##{project.id} \"#{project.title}\", can't return_for_changes from #{project.ship_status}"
        next
      end

      puts "  [FIX] Project ##{project.id} \"#{project.title}\", ship event ##{ship_event.id}: approved → needs_changes"

      project.return_for_changes! unless dry_run

      count += 1
    end

    puts
    puts "#{dry_run ? 'Would fix' : 'Fixed'} #{count} project(s)."
    puts "Run with DRY_RUN=false to apply." if dry_run
  end
end
