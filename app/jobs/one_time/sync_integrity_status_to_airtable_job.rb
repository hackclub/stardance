# frozen_string_literal: true

# Pushes one YSWS review's current integrity status to its Airtable submission
# row, and nothing else.
#
# The full payload sync (Certification::YswsAirtableSyncJob) only runs when a
# reviewer completes a review, so an integrity verdict decided afterwards never
# reaches Airtable — the submission row keeps the status it had at completion
# time. This writes just the "integrity_status" cell, leaving every other field
# — including the hours and justification the reviewer settled on — untouched.
#
# The work is guarded on timestamps: the integrity row's updated_at has to be
# newer than the review's airtable_synced_at for there to be anything to push.
# Re-running is a no-op, both because of that guard and because the Airtable
# value is compared before writing.
#
# Enqueued in bulk by OneTime::BackfillIntegrityStatusAirtableSyncJob; safe to
# run on its own for a single review.
#
# Usage:
#   OneTime::SyncIntegrityStatusToAirtableJob.perform_now(review_id)
class OneTime::SyncIntegrityStatusToAirtableJob < ApplicationJob
  queue_as :literally_whenever

  LOG_PREFIX = "[SyncIntegrityStatusToAirtable]"

  AIRTABLE_FIELD = "integrity_status"

  retry_on Faraday::Error, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(ysws_review_id)
    review = ::Certification::Ysws.find(ysws_review_id)
    integrity = review.integrity_check

    return log_skip(review, "no integrity check") if integrity.nil?
    return log_skip(review, "never synced to Airtable") if review.airtable_synced_at.nil?
    return log_skip(review, "integrity unchanged since last sync") if integrity.updated_at <= review.airtable_synced_at

    record = ::Certification::YswsAirtable.record_for(review.id)
    return log_skip(review, "no Airtable submission record") if record.nil?

    if record[AIRTABLE_FIELD] == integrity.status
      # Airtable already agrees, so only the local marker is behind. Stamping it
      # keeps the review out of a re-run's scope.
      stamp_synced(review)
      return log_skip(review, "Airtable already holds #{integrity.status}")
    end

    previous = record[AIRTABLE_FIELD]
    record[AIRTABLE_FIELD] = integrity.status
    record.save

    stamp_synced(review)

    Rails.logger.info "#{LOG_PREFIX} review=#{review.id} integrity=#{integrity.id} " \
                      "#{previous.inspect} -> #{integrity.status.inspect}"
    true
  end

  private

  # airtable_synced_at doubles as the "Airtable is current as of" marker that
  # both this job and Certification::YswsAirtableResyncJob read, so it is only
  # advanced when the rest of the payload was already current. A review still
  # owed a full resync (reviewed_at newer than the last sync) keeps its old
  # stamp — bumping it there would swallow that resync.
  def stamp_synced(review)
    return false if review.reviewed_at.present? && review.reviewed_at > review.airtable_synced_at

    review.update_column(:airtable_synced_at, Time.current)
    true
  end

  def log_skip(review, reason)
    Rails.logger.info "#{LOG_PREFIX} review=#{review.id} skipped — #{reason}"
    false
  end
end
