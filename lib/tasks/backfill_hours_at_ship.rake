# dry run:  bin/rails backfill:hours_at_ship
# to apply: bin/rails backfill:hours_at_ship DRY_RUN=false

namespace :backfill do
  desc "Backfill hours_at_ship on existing post_ship_events"
  task hours_at_ship: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    ship_events = Post::ShipEvent.where(hours_at_ship: nil)

    puts dry_run ? "[DRY RUN] No changes will be written." : "Writing changes to the database."
    puts
    count = ship_events.count

    if count.zero?
      puts "No post_ship_events need backfilling."
      next
    end

    puts "#{dry_run ? 'Would backfill' : 'Backfilling'} #{count} post_ship_event(s)."

    ship_events.find_each(&:recalculate_hours_at_ship) unless dry_run

    puts
    puts "#{dry_run ? 'Would backfill' : 'Backfilled'} #{count} post_ship_event(s)."
    puts "Run with DRY_RUN=false to apply." if dry_run
  end
end
