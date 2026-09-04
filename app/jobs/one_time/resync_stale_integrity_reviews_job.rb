# frozen_string_literal: true

# Replays the full Airtable submission payload for every YSWS review whose
# integrity verdict landed after the review was synced.
#
# Certification::Integrity now resyncs its review whenever the status moves, so
# this only exists to clear the rows that predate that callback: reviews synced
# while their check was still pending, which have been carrying that pending
# status and the un-deducted hours ever since.
#
# A full resync rather than a single-field patch, because a verdict moves three
# things at once: integrity_status, the override hours (deducted minutes come off
# the reviewer-approved total) and the justification text that explains them.
#
# Reviews the unified base has already picked up are reported, never enqueued:
# YswsAirtableSyncJob refuses to touch one, and that record has to be corrected
# by hand. in_unified_db is a local marker refreshed on demand, so a review
# promoted since its last check will still fail loudly in the job.
#
# DRY RUN BY DEFAULT: logs and returns the candidates, enqueues nothing.
#
# Usage:
#   OneTime::ResyncStaleIntegrityReviewsJob.perform_now                  # dry run
#   OneTime::ResyncStaleIntegrityReviewsJob.perform_now(dry_run: false)  # enqueues
class OneTime::ResyncStaleIntegrityReviewsJob < ApplicationJob
  queue_as :literally_whenever

  LOG_PREFIX = "[ResyncStaleIntegrityReviews]"

  Result = Struct.new(:enqueued, :needs_manual_fix, keyword_init: true)

  # Completed, synced reviews whose Airtable payload predates their integrity
  # verdict, found two ways because neither is sufficient alone.
  #
  # updated_at over-selects, since a claim or a justification edit bumps it too,
  # which costs a redundant resync rather than a wrong one. On its own it also
  # misses rows the retired status-only patch touched: that job stamped
  # airtable_synced_at after writing a single cell, hiding a row whose hours were
  # never recomputed. A verdict later than the review's own completion catches
  # those, since the payload written at completion cannot have carried it.
  def scope
    ::Certification::Ysws
      .joins(:integrity_check)
      .where.not(reviewed_at: nil)
      .where.not(airtable_synced_at: nil)
      .where(
        "certification_integrities.updated_at > certification_ysws_reviews.airtable_synced_at " \
        "OR certification_integrities.reviewed_at > certification_ysws_reviews.reviewed_at"
      )
  end

  def perform(dry_run: true)
    resyncable, promoted = scope.pluck(:id, :in_unified_db).partition { |(_, unified)| unified.blank? }
    review_ids = resyncable.map(&:first)
    manual_ids = promoted.map(&:first)

    if manual_ids.any?
      Rails.logger.warn "#{LOG_PREFIX} #{manual_ids.size} review(s) already in the unified base, " \
                        "correct by hand: #{manual_ids.inspect}"
    end

    if dry_run
      Rails.logger.info "#{LOG_PREFIX} DRY RUN, would enqueue #{review_ids.size} resync(s): #{review_ids.inspect}"
      return Result.new(enqueued: review_ids, needs_manual_fix: manual_ids)
    end

    review_ids.each { |id| ::Certification::YswsAirtableSyncJob.perform_later(id) }
    Rails.logger.info "#{LOG_PREFIX} Enqueued #{review_ids.size} resync(s)"

    Result.new(enqueued: review_ids, needs_manual_fix: manual_ids)
  end
end
