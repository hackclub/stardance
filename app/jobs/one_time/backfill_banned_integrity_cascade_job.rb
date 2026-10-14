# frozen_string_literal: true

# Applies the banned-integrity cascade to projects decided before that cascade
# existed.
#
# Certification::Integrity now settles a whole project when one of its checks is
# banned: every still-pending check on the project takes the same verdict, and
# the project's pending YSWS reviews are auto-rejected. That runs from an
# after_commit, so it only ever fires on new decisions — projects banned earlier
# still carry pending checks in the fraud queue and pending YSWS reviews nobody
# can judge.
#
# This walks every project that already has a banned check and does the same two
# things by hand. Both halves are idempotent (a check is only touched while
# pending, and YswsReviewRejector#call returns early unless the review is
# pending), so a re-run reports zero work rather than doubling up.
#
# Project.with_deleted is not optional here: banning a user soft-deletes their
# projects, and a good share of the banned population is exactly that.
#
# Ship events that a reviewer already settled as something other than a ban are
# left completely alone — see #settled_ship_event_ids. Every run reports how many
# checks and reviews it walked past for that reason, so the exclusion is never
# silent.
#
# Backfilled checks are credited to the account YswsReviewRejector already uses
# for automated decisions rather than to whoever made the original call — these
# are machine-written rows, and the justification names the check they came from.
#
# DRY RUN BY DEFAULT: logs and returns the plan and writes nothing. Pass
# dry_run: false to persist.
#
# Usage:
#   OneTime::BackfillBannedIntegrityCascadeJob.perform_now                           # dry run
#   OneTime::BackfillBannedIntegrityCascadeJob.perform_now(project_ids: [531, 2461]) # dry run, subset
#   OneTime::BackfillBannedIntegrityCascadeJob.perform_now(dry_run: false)           # writes
class OneTime::BackfillBannedIntegrityCascadeJob < ApplicationJob
  queue_as :literally_whenever

  LOG_PREFIX = "[BackfillBannedIntegrityCascade]"

  WHODUNNIT = "OneTime::BackfillBannedIntegrityCascadeJob"

  # Verdicts that mean a ship event was looked at and not banned.
  SETTLED_STATUSES = %w[auto_passed manually_passed deducted].freeze

  # Projects carrying at least one banned check, soft-deleted ones included.
  def scope(project_ids: nil)
    projects = ::Project.with_deleted
      .joins(:integrity_checks)
      .where(certification_integrities: { status: :banned })
      .distinct
    project_ids.present? ? projects.where(id: project_ids) : projects
  end

  def perform(dry_run: true, project_ids: nil)
    reviewer = ::Certification::YswsReviewRejector.reviewer

    if reviewer.nil?
      Rails.logger.error "#{LOG_PREFIX} Aborting — no user ##{::Certification::YswsReviewRejector::REVIEWER_ID} " \
                         "to attribute the backfilled checks to (a decided check requires a reviewer)."
      return
    end

    projects = scope(project_ids: project_ids).to_a
    return log_plan(projects) if dry_run

    summary = { projects: 0, checks_cascaded: 0, reviews: 0, devlog_reviews: 0, synced: 0, sync_skipped: 0 }

    skipped = { checks: 0, reviews: 0 }

    projects.each do |project|
      settled  = settled_ship_event_ids(project)
      cascaded = 0
      results  = []

      PaperTrail.request(whodunnit: WHODUNNIT) do
        cascaded = cascade_checks(project, reviewer, settled)
        results  = reject_reviews(project, settled)
      end

      skipped[:checks]  += skipped_checks(project, settled).count
      skipped[:reviews] += skipped_reviews(project, settled).count

      rejected = results.select(&:rejected)
      next if cascaded.zero? && rejected.empty?

      summary[:projects]        += 1
      summary[:checks_cascaded] += cascaded
      summary[:reviews]         += rejected.size
      summary[:devlog_reviews]  += rejected.sum(&:devlog_reviews)
      summary[:synced]          += rejected.count(&:synced)
      summary[:sync_skipped]    += rejected.count { |result| !result.synced }
    end

    summary.merge!(checks_left_on_settled_ships: skipped[:checks], reviews_left_on_settled_ships: skipped[:reviews])

    Rails.logger.info "#{LOG_PREFIX} Cascaded #{summary[:checks_cascaded]} check(s) and rejected " \
                      "#{summary[:reviews]} review(s) / #{summary[:devlog_reviews]} devlog review(s) " \
                      "across #{summary[:projects]} project(s); " \
                      "#{summary[:synced]} synced, #{summary[:sync_skipped]} skipped (no integrity check); " \
                      "left alone on already-settled ship events: #{skipped[:checks]} check(s), " \
                      "#{skipped[:reviews]} review(s)"
    summary
  end

  private

  # Ship events already settled as anything other than a ban — auto-passed,
  # manually passed, deducted — and never banned in their own right.
  #
  # Production has several integrity rows per ship event (the unique index in
  # schema.rb isn't enforced there), so banning a leftover pending row on one of
  # these would leave the ship holding a passing verdict and a fraud verdict at
  # once, with YswsAirtableSyncJob#integrity_check_for picking between them by
  # an unordered find_by. The backfill leaves those ship events entirely alone —
  # checks and reviews both — and reports how many it walked past.
  def settled_ship_event_ids(project)
    checks = project.integrity_checks
    checks.where(status: SETTLED_STATUSES).pluck(:ship_event_id) - checks.banned.pluck(:ship_event_id)
  end

  # Copies the project's fraud verdict onto its still-pending checks. Runs before
  # the YSWS rejections: YswsAirtableSyncJob reads each review's own ship event's
  # integrity row, so every row has to carry the verdict before a sync enqueues.
  def cascade_checks(project, reviewer, settled)
    source = source_check(project)
    cascaded = 0

    pending_checks(project, settled).find_each do |check|
      check.skip_decision_cascade = true
      check.paper_trail_event = "cascaded_decision"
      check.update!(
        status: :banned,
        reviewer_id: reviewer.id,
        decision_justification: justification_for(source)
      )
      cascaded += 1
    end

    cascaded
  end

  # The ban this backfill derives from — the earliest, so a project banned more
  # than once reads as settled from the first verdict.
  def source_check(project)
    project.integrity_checks.banned.order(:reviewed_at, :id).first
  end

  # Rejects the project's pending reviews one at a time rather than through
  # YswsReviewRejector.reject_pending_for_project!, so reviews hanging off a
  # settled ship event can be held back.
  def reject_reviews(project, settled)
    pending_reviews(project, settled).includes(:devlog_reviews).map do |review|
      ::Certification::YswsReviewRejector.new(review, reason: :banned).call
    end
  end

  def pending_checks(project, settled)
    project.integrity_checks.pending.where.not(ship_event_id: settled)
  end

  def pending_reviews(project, settled)
    ::Certification::Ysws.pending.where(project_id: project.id).where.not(post_ship_event_id: settled)
  end

  def skipped_checks(project, settled)
    project.integrity_checks.pending.where(ship_event_id: settled)
  end

  def skipped_reviews(project, settled)
    ::Certification::Ysws.pending.where(project_id: project.id, post_ship_event_id: settled)
  end

  def justification_for(source)
    banned_on = source&.reviewed_at&.to_date
    "Backfilled from integrity review ##{source&.id} (banned #{banned_on || 'date unknown'})."
  end

  def log_plan(projects)
    plan = projects.filter_map do |project|
      settled = settled_ship_event_ids(project)
      checks  = pending_checks(project, settled).count
      reviews = pending_reviews(project, settled).includes(:devlog_reviews, :integrity_check).to_a
      left    = { checks: skipped_checks(project, settled).count, reviews: skipped_reviews(project, settled).count }
      next if checks.zero? && reviews.empty? && left.values.sum.zero?

      {
        project_id: project.id,
        checks: checks,
        reviews: reviews.size,
        devlog_reviews: reviews.sum { |review| review.devlog_reviews.count },
        sync_skipped: reviews.count { |review| review.integrity_check.blank? },
        checks_left_on_settled_ships: left[:checks],
        reviews_left_on_settled_ships: left[:reviews]
      }
    end

    totals = plan.each_with_object(Hash.new(0)) do |row, acc|
      row.except(:project_id).each { |key, value| acc[key] += value }
    end

    Rails.logger.info "#{LOG_PREFIX} DRY RUN — #{plan.size} project(s): " \
                      "#{totals[:checks]} check(s) to cascade, #{totals[:reviews]} review(s) " \
                      "(#{totals[:devlog_reviews]} devlog review(s)) to reject, " \
                      "#{totals[:sync_skipped]} without an integrity check to sync; " \
                      "leaving #{totals[:checks_left_on_settled_ships]} check(s) and " \
                      "#{totals[:reviews_left_on_settled_ships]} review(s) on already-settled ship events. " \
                      "#{plan.inspect}"
    plan
  end
end
