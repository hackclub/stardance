# The reship auto-approve path called Project#approve! before the project had
# gone through under_review, so the AASM guard silently no-op'd and the
# project got stuck on "submitted" even though its ship event was already
# marked "approved" (see Projects::ShipsController#create).
#
# dry run:  bin/rails backfill:stuck_reship_approvals
# to apply: bin/rails backfill:stuck_reship_approvals DRY_RUN=false

namespace :backfill do
  desc "Move projects stuck on 'submitted' with an approved ship event into 'approved'"
  task stuck_reship_approvals: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    puts dry_run ? "[DRY RUN] No changes will be written." : "Writing changes to the database."
    puts

    count = 0
    failed = 0

    Project.where(ship_status: "submitted").find_each do |project|
      ship_event = project.last_ship_event

      next unless ship_event&.certification_status == "approved"

      unless project.may_start_review?
        puts "  [SKIP] Project ##{project.id} \"#{project.title}\", can't start_review from #{project.ship_status}"
        next
      end

      puts "  [FIX] Project ##{project.id} \"#{project.title}\", ship event ##{ship_event.id}: submitted → approved"

      if dry_run
        count += 1
        next
      end

      begin
        project.with_lock do
          # State can shift between the may_start_review? check above and the
          # lock, so re-check inside the transaction before transitioning.
          raise ActiveRecord::Rollback unless project.may_start_review?

          project.start_review!
          project.approve!
          count += 1
        end
      rescue => e
        failed += 1
        puts "  [FAIL] Project ##{project.id} \"#{project.title}\": #{e.class} #{e.message}"
      end
    end

    puts
    puts "#{dry_run ? 'Would fix' : 'Fixed'} #{count} project(s)."
    puts "Skipped #{failed} project(s) due to errors — see [FAIL] lines above." if failed.positive?
    puts "Run with DRY_RUN=false to apply." if dry_run
  end
end
