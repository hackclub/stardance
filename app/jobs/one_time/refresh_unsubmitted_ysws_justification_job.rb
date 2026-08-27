# frozen_string_literal: true

# Rewrites the override-hours justification on every Airtable submission row the
# Unified YSWS base hasn't picked up yet.
#
# Certification::YswsAirtableSyncJob writes that text once, at review completion,
# so a row synced before the justification gained a field — the commit-activity
# rating, the reship note, the Hackatime account and project names — keeps the
# older, thinner text forever. Rows whose "Automation - YSWS Record ID" is still
# empty have not been read downstream, so rewriting them is safe: the grant side
# has not seen the old text, and no downstream record has to be corrected.
#
# Candidates come from Airtable, since only Airtable knows which rows the
# automation has claimed. For each hit the justification is rebuilt from current
# Stardance data and written back whole, not patched line by line, so the devlog
# tallies, hours, shop orders and integrity note all come along.
#
# Only the justification is written. The override hours are deliberately left
# alone: a reviewer or the fraud department may have adjusted them by hand after
# the sync, and this job has no way to tell that apart from a stale value.
# Nothing in Stardance is written.
#
# DRY RUN BY DEFAULT: logs what it would rewrite and writes nothing. Pass
# dry_run: false to persist.
#
# Usage:
#   OneTime::RefreshUnsubmittedYswsJustificationJob.perform_now                  # dry run
#   OneTime::RefreshUnsubmittedYswsJustificationJob.perform_now(dry_run: false)  # writes
class OneTime::RefreshUnsubmittedYswsJustificationJob < ApplicationJob
  include OneTime::JustificationRebuilder

  queue_as :literally_whenever

  LOG_PREFIX = "[RefreshUnsubmittedYswsJustification]"

  JUSTIFICATION_FIELD = "Optional - Override Hours Spent Justification"
  REVIEW_ID_FIELD = "review_id"
  UNIFIED_RECORD_ID_FIELD = ::Certification::YswsReviewUndoer::UNIFIED_RECORD_ID_FIELD

  def perform(dry_run: true)
    records = unsubmitted_records
    Rails.logger.info "#{LOG_PREFIX} #{records.size} candidate row(s) from Airtable"

    summary = { rewritten: 0, unchanged: 0, skipped: 0, failed: 0 }

    records.each do |record|
      outcome = process(record, dry_run: dry_run)
      summary[outcome] += 1
    end

    Rails.logger.info "#{LOG_PREFIX} #{dry_run ? 'DRY RUN — would rewrite' : 'Rewrote'} " \
                      "#{summary[:rewritten]} row(s); #{summary[:unchanged]} already current, " \
                      "#{summary[:skipped]} skipped, #{summary[:failed]} failed"
    summary
  end

  private

  # Rows the unified automation hasn't stamped a record id onto. The formula is
  # re-checked in Ruby because the field is written by the other base's
  # automation and can come back as an empty array rather than an empty string.
  def unsubmitted_records
    ::Certification::YswsAirtable.table.all(
      filter: "{#{UNIFIED_RECORD_ID_FIELD}} = ''",
      fields: [ REVIEW_ID_FIELD, UNIFIED_RECORD_ID_FIELD, JUSTIFICATION_FIELD ]
    ).select { |record| Array(record[UNIFIED_RECORD_ID_FIELD]).all?(&:blank?) }
  end

  def process(record, dry_run:)
    review = review_for(record)
    return log_skip(record, "no review in Stardance") if review.nil?

    # Hardware projects carry no integrity check; the rebuilt text says so.
    justification = build_justification(
      review,
      review.integrity_check,
      review.approved_minutes_total,
      deducted_minutes_for(review)
    )
    return :unchanged if record[JUSTIFICATION_FIELD] == justification

    if dry_run
      Rails.logger.info "#{LOG_PREFIX} DRY RUN — review=#{review.id} record=#{record.id} " \
                        "would have its justification rewritten"
      return :rewritten
    end

    record[JUSTIFICATION_FIELD] = justification
    record.save

    Rails.logger.info "#{LOG_PREFIX} review=#{review.id} record=#{record.id} justification rewritten"
    :rewritten
  rescue StandardError => e
    Rails.logger.error "#{LOG_PREFIX} record=#{record.id} failed: #{e.class}: #{e.message}"
    Sentry.capture_exception(e, extra: { airtable_record_id: record.id })
    :failed
  end

  # The deduction is reported inside the text, so it has to be recomputed even
  # though the hours field itself is left untouched.
  def deducted_minutes_for(review)
    integrity_check = review.integrity_check
    integrity_check&.deducted? ? integrity_check.deduction_minutes.to_i : 0
  end

  def review_for(record)
    review_id = record[REVIEW_ID_FIELD].presence
    return nil if review_id.nil?

    ::Certification::Ysws
      .includes(:reviewer, :devlog_reviews, ship_cert: :reviewer, user: { shop_orders: :shop_item })
      .find_by(id: review_id)
  end

  def log_skip(record, reason)
    Rails.logger.info "#{LOG_PREFIX} record=#{record.id} skipped — #{reason}"
    :skipped
  end
end
