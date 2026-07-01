# Promotes AI-classified hardware projects (project_type == "Hardware") that
# never entered the hardware flow (hardware_stage still nil) to the "design"
# entry stage, so they move into the hardware review flow instead of sitting in
# limbo — and out of the software ship-review queue.
#
# Setting hardware_stage flips Project#hardware? to true, which enables the
# Lookout recorder and the hardware shipping/funding gates. "design" is the safe
# entry stage: no funding grant, and design-phase time is uncounted for payout.
# All the real logic (scope, audited save) lives in the job; this is just a
# visible, dry-run-by-default runner. See OneTime::BackfillHardwareStageJob.
#
# dry run:  bin/rails backfill:hardware_stage
# to apply: bin/rails backfill:hardware_stage DRY_RUN=false

namespace :backfill do
  desc "Promote AI-classified hardware projects (no hardware_stage) into the hardware flow at the design stage"
  task hardware_stage: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    puts dry_run ? "[DRY RUN] No changes will be written." : "Writing changes to the database."
    puts

    result = OneTime::BackfillHardwareStageJob.perform_now(dry_run: dry_run, stage: "design")

    if dry_run
      ids = Array(result)
      Project.where(id: ids).order(:id).each do |project|
        puts "  [WOULD SET] Project ##{project.id} \"#{project.title}\" → hardware_stage=design"
      end
      puts
      puts "Would promote #{ids.size} project(s)."
      puts "Run with DRY_RUN=false to apply."
    else
      puts "Promoted #{result} project(s) to hardware_stage=design."
    end
  end
end
