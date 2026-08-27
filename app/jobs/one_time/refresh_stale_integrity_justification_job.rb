# frozen_string_literal: true

# Rewrites Airtable submission rows whose override-hours justification still
# says the integrity check is waiting, when it isn't any more.
#
# Certification::YswsAirtableSyncJob writes that justification once, at review
# completion. A check that was still pending then leaves the line "Waiting for
# manual heartbeat review." baked into the text, and a later verdict — passed,
# deducted, banned — never rewrites it. Those rows read as awaiting review long
# after the call was made, and, when the verdict was a deduction, the text is
# missing the deduction entirely.
#
# Candidates come from Airtable rather than the database: the stale sentence is
# the only reliable marker, and it exists nowhere in Stardance. For each hit the
# justification is rebuilt from current Stardance data and written back — the
# whole text, not a patched line, so the devlog tallies, hours and shop orders
# come along with it.
#
# The justification is rebuilt through OneTime::JustificationRebuilder, a copy
# of YswsAirtableSyncJob's builder shared by the one-time cleanups — the sync job
# and the copy are allowed to drift once these have run.
#
# The override hours ride along with the text: a verdict of deducted takes its
# deduction off the reviewer-approved total, so a row whose justification is
# stale usually has hours to match. Nothing in Stardance is written, and no
# Airtable field outside those two is touched.
#
# DRY RUN BY DEFAULT: logs what it would rewrite and writes nothing. Pass
# dry_run: false to persist.
#
# Usage:
#   OneTime::RefreshStaleIntegrityJustificationJob.perform_now                  # dry run
#   OneTime::RefreshStaleIntegrityJustificationJob.perform_now(dry_run: false)  # writes
class OneTime::RefreshStaleIntegrityJustificationJob < ApplicationJob
  include OneTime::JustificationRebuilder

  queue_as :literally_whenever

  LOG_PREFIX = "[RefreshStaleIntegrityJustification]"

  JUSTIFICATION_FIELD = "Optional - Override Hours Spent Justification"
  HOURS_FIELD = "Optional - Override Hours Spent"
  STATUS_FIELD = "integrity_status"
  REVIEW_ID_FIELD = "review_id"

  # The sentence that marks a row as stale.
  STALE_NOTE = INTEGRITY_JUSTIFICATION_NOTES.fetch("pending")

  def perform(dry_run: true)
    records = stale_records
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

  # Rows still carrying the waiting sentence while Airtable's own status says the
  # check has since been decided. Keying the status side off Airtable rather than
  # Stardance keeps this to rows that are internally contradictory — a row whose
  # check is genuinely still pending is not stale, it is just waiting.
  def stale_records
    filter = "AND(FIND('#{STALE_NOTE}', {#{JUSTIFICATION_FIELD}}) > 0, {#{STATUS_FIELD}} != 'pending')"

    ::Certification::YswsAirtable.table.all(
      filter: filter,
      fields: [ REVIEW_ID_FIELD, STATUS_FIELD, JUSTIFICATION_FIELD, HOURS_FIELD ]
    )
  end

  def process(record, dry_run:)
    review = review_for(record)
    return log_skip(record, "no review in Stardance") if review.nil?

    integrity_check = review.integrity_check
    return log_skip(record, "no integrity check") if integrity_check.nil?

    # Stardance disagreeing with Airtable's status means rebuilding would put the
    # same waiting sentence straight back. Left alone and reported.
    return log_skip(record, "integrity ##{integrity_check.id} is still pending") if integrity_check.pending?

    changes = build_fields(review, integrity_check).reject { |field, value| current?(record, field, value) }
    return :unchanged if changes.empty?

    if dry_run
      Rails.logger.info "#{LOG_PREFIX} DRY RUN — review=#{review.id} record=#{record.id} " \
                        "would take the #{integrity_check.status} note, changing #{changes.keys.inspect}"
      return :rewritten
    end

    changes.each { |field, value| record[field] = value }
    record.save

    Rails.logger.info "#{LOG_PREFIX} review=#{review.id} record=#{record.id} " \
                      "rewritten with the #{integrity_check.status} note, changed #{changes.keys.inspect}"
    :rewritten
  rescue StandardError => e
    Rails.logger.error "#{LOG_PREFIX} record=#{record.id} failed: #{e.class}: #{e.message}"
    Sentry.capture_exception(e, extra: { airtable_record_id: record.id })
    :failed
  end

  def review_for(record)
    review_id = record[REVIEW_ID_FIELD].presence
    return nil if review_id.nil?

    ::Certification::Ysws
      .includes(:reviewer, :devlog_reviews, ship_cert: :reviewer, user: { shop_orders: :shop_item })
      .find_by(id: review_id)
  end

  # Airtable hands numbers back as Integer or Float depending on the stored
  # value, so 3 and 3.0 have to read as the same hours.
  def current?(record, field, value)
    field == HOURS_FIELD ? record[field].to_f == value.to_f : record[field] == value
  end

  def log_skip(record, reason)
    Rails.logger.info "#{LOG_PREFIX} record=#{record.id} skipped — #{reason}"
    :skipped
  end
end
