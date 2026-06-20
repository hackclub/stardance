# Some projects got returned by shipwrights before recertification was there,
# so their ship_event is stuck on "pending" even though the review is "returned".
# This fixes that so the "Changes requested" badge shows up and they can resubmit.
#
# dry run:  bin/rails backfill:returned_ship_events
# to apply: bin/rails backfill:returned_ship_events DRY_RUN=false

namespace :backfill do
  desc "Fix ship events stuck on 'pending' for projects that were already returned"
  task returned_ship_events: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    puts dry_run ? "[DRY RUN] No changes will be written." : "Writing changes to the database."
    puts

    affected = Certification::Ship
      .where(status: :returned)
      .joins(:project)
      .where(projects: { ship_status: "needs_changes" })
      .includes(:project)

    count = 0

    affected.find_each do |ship_review|
      project    = ship_review.project
      ship_event = project.last_ship_event

      unless ship_event
        puts "  [SKIP] Project ##{project.id} \"#{project.title}\", no ship event found"
        next
      end

      unless ship_event.certification_status == "pending"
        puts "  [SKIP] Project ##{project.id} \"#{project.title}\", ship event already has status: #{ship_event.certification_status}"
        next
      end

      puts "  [FIX] Project ##{project.id} \"#{project.title}\", ship event ##{ship_event.id}: pending → returned"

      unless dry_run
        ship_event.update!(certification_status: "returned")
      end

      count += 1
    end

    puts
    puts "#{dry_run ? 'Would fix' : 'Fixed'} #{count} ship event(s)."
    puts "Run with DRY_RUN=false to apply." if dry_run
  end
end
