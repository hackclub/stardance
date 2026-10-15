# frozen_string_literal: true

# Seeds Hackatime projects for hardware projects that already existed when the
# Lapse migration landed.
#
# Project::EnsureHackatimeProjectsJob only fires on an event: a project turning
# hardware, a rename, or a member joining. Projects that were already hardware
# before that callback existed never fire any of those again, so they'd send
# their builders to Lapse with no Hackatime project to file against. This walks
# them once.
#
# DRY RUN BY DEFAULT: logs and returns the candidate ids and enqueues nothing.
# Pass dry_run: false to actually enqueue. Placeholder-titled projects are
# skipped (the seeding job would refuse them anyway) and reported separately, so
# you can see how many are waiting on a rename rather than on this backfill.
#
# Safe to re-run: the seeding job is idempotent per (user, name) and only seeds
# when Hackatime positively reports the project missing.
class OneTime::BackfillHackatimeProjectsJob < ApplicationJob
  queue_as :literally_whenever

  # Hardware projects where at least one MEMBER still has no Hackatime project
  # linked. A project-level "has no rows at all" check would skip a project
  # where one member is linked and another isn't - and seeding is per-member.
  def self.candidates
    Project.where.not(hardware_stage: nil).where(<<~SQL.squish)
      EXISTS (
        SELECT 1 FROM project_memberships pm
        WHERE pm.project_id = projects.id
          AND NOT EXISTS (
            SELECT 1 FROM user_hackatime_projects uhp
            WHERE uhp.project_id = projects.id AND uhp.user_id = pm.user_id
          )
      )
    SQL
  end

  def perform(dry_run: true, batch_size: 200)
    seeded = []
    skipped_placeholder = []

    self.class.candidates.find_each(batch_size: batch_size) do |project|
      if project.placeholder_title?
        skipped_placeholder << project.id
        next
      end

      seeded << project.id
      Project::EnsureHackatimeProjectsJob.perform_later(project.id) unless dry_run
    end

    Rails.logger.info(
      "BackfillHackatimeProjects: #{seeded.size} to seed, " \
      "#{skipped_placeholder.size} skipped as placeholder-titled#{" (DRY RUN)" if dry_run}"
    )

    { seeded: seeded, skipped_placeholder: skipped_placeholder, dry_run: dry_run }
  end
end
