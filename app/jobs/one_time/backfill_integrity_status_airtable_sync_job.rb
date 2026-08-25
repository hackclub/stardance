# frozen_string_literal: true

# Brings Airtable's integrity_status back in line for every YSWS review whose
# integrity verdict moved after the review was synced.
#
# Certification::YswsAirtableSyncJob writes the whole submission payload when a
# reviewer completes a review, integrity status included. Integrity review runs
# on its own clock, though: a check that was pending (or auto-passed) at
# completion time can later be manually passed, deducted, or banned — including
# through Certification::Integrity's project-wide cascade — and nothing pushes
# that verdict to Airtable. Those rows have been carrying a stale
# integrity_status ever since.
#
# This finds them by comparing each review's integrity row's updated_at against
# its airtable_synced_at, and hands each one to
# OneTime::SyncIntegrityStatusToAirtableJob, which re-checks that comparison and
# writes the single field. Reviews that were never synced are out of scope —
# they have no submission row to patch, and the daily
# Certification::YswsAirtableResyncJob already owns them.
#
# DRY RUN BY DEFAULT: logs and returns the candidate ids and enqueues nothing.
# Pass dry_run: false to enqueue.
#
# Usage:
#   OneTime::BackfillIntegrityStatusAirtableSyncJob.perform_now                  # dry run
#   OneTime::BackfillIntegrityStatusAirtableSyncJob.perform_now(dry_run: false)  # enqueues
class OneTime::BackfillIntegrityStatusAirtableSyncJob < ApplicationJob
  queue_as :literally_whenever

  LOG_PREFIX = "[BackfillIntegrityStatusAirtableSync]"

  # Synced reviews whose integrity row has been touched since that sync.
  #
  # updated_at is the only signal available: certification_integrities carries
  # no per-column history beyond PaperTrail, and a status change always bumps
  # it. It over-selects — an unrelated column change (a claim, a justification
  # edit) also bumps updated_at — which is why the helper compares the Airtable
  # value before writing.
  def scope
    ::Certification::Ysws
      .joins(:integrity_check)
      .where.not(airtable_synced_at: nil)
      .where("certification_integrities.updated_at > certification_ysws_reviews.airtable_synced_at")
  end

  def perform(dry_run: true)
    review_ids = scope.pluck(:id)

    if dry_run
      Rails.logger.info "#{LOG_PREFIX} DRY RUN — would enqueue #{review_ids.size} " \
                        "integrity status sync(s): #{review_ids.inspect}"
      return review_ids
    end

    review_ids.each { |id| OneTime::SyncIntegrityStatusToAirtableJob.perform_later(id) }

    Rails.logger.info "#{LOG_PREFIX} Enqueued #{review_ids.size} integrity status sync(s)"
    review_ids
  end
end
