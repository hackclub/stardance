# frozen_string_literal: true

module Certification
  # Reverses a completed YSWS review so it lands back in the pending queue, and
  # removes the review's Airtable submission record.
  #
  # This is the inverse of Admin::Certification::YswsController#complete: it
  # clears every field that decision stamped, drops the claim so the review is
  # up for grabs again, and deletes the row the sync job upserted into the YSWS
  # Project Submission table.
  #
  # Devlog verdicts survive by default, so the reviewer's per-devlog work is
  # still there and the review can simply be completed again. Pass
  # `reset_devlogs: true` to take those back to pending as well — that clears
  # each verdict's justification and approved minutes, so the whole review has
  # to be redone from scratch.
  #
  # Returned reviews are out of scope: #return_to_ship_cert also opens a recert
  # Certification::Ship and transfers the external certification id to it, and
  # undoing the returned_at stamp alone would leave the project sitting in both
  # queues at once.
  #
  # It does NOT reach the Unified YSWS base. Once a submission has been picked
  # up there, that downstream record has to be removed by hand — the record id
  # is reported back on the Result so the caller can log it before it's gone.
  class YswsReviewUndoer
    # The Airtable field holding the Unified YSWS base's record id, populated by
    # the automation on that side once a submission is picked up.
    UNIFIED_RECORD_ID_FIELD = "Automation - YSWS Record ID"

    Result = Struct.new(:undone, :airtable_record_deleted, :unified_record_id, :devlog_reviews_reset,
                        keyword_init: true)

    attr_reader :review, :reset_devlogs

    def initialize(review, reset_devlogs: false)
      @review = review
      @reset_devlogs = reset_devlogs
    end

    def call
      return refused unless undoable?

      # Airtable first, on purpose: it can't take part in the DB transaction, so
      # a failed delete has to abort before anything is written rather than
      # leaving a stale submission row behind a pending review.
      record = ::Certification::YswsAirtable.record_for(review.id)
      unified_record_id = record&.[](UNIFIED_RECORD_ID_FIELD).presence
      deleted = delete_airtable_record(record)

      undone = false
      devlogs_reset = 0
      review.with_lock do
        # Re-check under the row lock so a double-submit can't undo twice.
        next unless undoable?

        # update! rather than the #complete action's update_columns, so the
        # audit trail carries the reversal.
        review.update!(
          reviewed_at: nil,
          reviewer_id: nil,
          in_unified_db: nil,
          airtable_synced_at: nil,
          claimed_by_id: nil,
          claimed_at: nil
        )
        if reset_devlogs
          # Certification::Devlog#reset_to_pending! clears the status, the
          # approved minutes and the justification in one go.
          devlogs = review.devlog_reviews.to_a
          devlogs.each(&:reset_to_pending!)
          devlogs_reset = devlogs.size
        end

        undone = true
      end
      return refused unless undone

      Result.new(undone: true, airtable_record_deleted: deleted, unified_record_id: unified_record_id,
                 devlog_reviews_reset: devlogs_reset)
    end

    private

    # Mirrors Admin::Certification::YswsPolicy#undo?.
    def undoable?
      review.reviewed_at? && review.returned_at.nil?
    end

    def refused
      Result.new(undone: false, airtable_record_deleted: false, unified_record_id: nil, devlog_reviews_reset: 0)
    end

    # True when a record was found and deleted. A record that isn't there is
    # success — there is nothing left to remove.
    def delete_airtable_record(record)
      return false if record.nil?

      record.destroy
      true
    rescue Norairrecord::RecordNotFoundError
      false
    end
  end
end
