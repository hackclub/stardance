# frozen_string_literal: true

# Brings legacy hardware projects into the new hardware flow.
#
# Projects shipped before the hardware flow existed (hardware_stage column added
# 2026-06-02) sit at hardware_stage = nil, so Project#hardware? is false for them
# even when they are genuine hardware builds. Once Project::TypeCheckJob has run,
# the AI type classifier marks such projects with project_type == "Hardware";
# this job promotes those into the flow by stamping hardware_stage.
#
# DRY RUN BY DEFAULT: logs and returns the candidate ids and writes nothing. Pass
# dry_run: false to persist. Always dry-run first and eyeball the list — setting
# hardware_stage flips Project#hardware? to true, which enables the Lookout
# recorder and the hardware shipping/funding gates for that project going forward.
#
# Stage defaults to "design", the flow's entry stage, which is the safe choice
# for already-shipped legacy projects:
#   * it does not imply a funding grant;
#   * design-phase time is not credited toward build payout, so it cannot change
#     a payout; and
#   * a project in scope cannot already have a funding request (funding requires
#     a stage to be set first), so the funding-stage lock never trips.
#
# Writes go through save(validate: false) so legacy rows that would fail today's
# unrelated validations (URL format, banner content type, ...) still get
# classified, while PaperTrail (audit) and the Gorse / semantic-search re-index
# callbacks still fire. The write is wrapped in PaperTrail.request so the audit
# version is attributed to this job.
#
# WARNING — devlog phase interaction: do NOT re-run OneTime::BackfillDevlogPhaseJob
# after this. That job stamps every nil-phase devlog with its project's current
# hardware_stage; once these projects have a stage, a re-run would back-date their
# old devlogs into that phase. (Defaulting to "design" keeps that harmless, since
# design-phase time is uncounted, but a "build" run would over-credit payout.)
class OneTime::BackfillHardwareStageJob < ApplicationJob
  queue_as :literally_whenever

  WHODUNNIT = "OneTime::BackfillHardwareStageJob"

  # AI-typed hardware projects not yet in the hardware flow.
  def scope
    Project.where(project_type: "Hardware", hardware_stage: nil)
  end

  def perform(dry_run: true, stage: "design")
    unless Project::HARDWARE_STAGES.include?(stage)
      raise ArgumentError, "stage must be one of #{Project::HARDWARE_STAGES.inspect}, got #{stage.inspect}"
    end

    ids = scope.pluck(:id)

    if dry_run
      Rails.logger.info "[BackfillHardwareStage] DRY RUN — would set hardware_stage=#{stage} on #{ids.size} project(s): #{ids.inspect}"
      return ids
    end

    updated = 0
    PaperTrail.request(whodunnit: WHODUNNIT) do
      scope.find_each do |project|
        project.hardware_stage = stage
        project.save!(validate: false)
        updated += 1
      end
    end

    Rails.logger.info "[BackfillHardwareStage] Set hardware_stage=#{stage} on #{updated} project(s)"
    updated
  end
end
