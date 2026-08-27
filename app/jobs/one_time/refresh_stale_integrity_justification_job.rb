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
# This is a one-time cleanup, so the justification builder below is a copy of
# YswsAirtableSyncJob's rather than an extraction — the two are allowed to drift
# once this has run, and this file gets deleted.
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
  queue_as :literally_whenever

  LOG_PREFIX = "[RefreshStaleIntegrityJustification]"

  JUSTIFICATION_FIELD = "Optional - Override Hours Spent Justification"
  HOURS_FIELD = "Optional - Override Hours Spent"
  STATUS_FIELD = "integrity_status"
  REVIEW_ID_FIELD = "review_id"

  # One line per Certification::Integrity status, embedded in the justification.
  # Uses fetch so an unmapped new status fails loudly.
  INTEGRITY_JUSTIFICATION_NOTES = {
    "auto_passed" => "Passed automatic heartbeat checks.",
    "pending" => "Waiting for manual heartbeat review.",
    "manually_passed" => "Passed manual heartbeat review.",
    "deducted" => "Hours deducted during manual review.",
    "banned" => "Project rejected due to manual review of heartbeats."
  }.freeze

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

  # ---- Copied from Certification::YswsAirtableSyncJob ---------------------
  # Kept verbatim (minus the argument threading) so a rewritten row is
  # indistinguishable from one the completion sync wrote today.

  # The two fields the completion sync derives from the integrity verdict. A
  # deduction comes off the reviewer-approved total before the hours are
  # reported, so both move together.
  def build_fields(review, integrity_check)
    total_approved_minutes = review.approved_minutes_total
    deducted_minutes = integrity_check.deducted? ? integrity_check.deduction_minutes.to_i : 0
    net_approved_minutes = [ total_approved_minutes - deducted_minutes, 0 ].max

    {
      JUSTIFICATION_FIELD => build_justification(review, integrity_check, total_approved_minutes, deducted_minutes),
      HOURS_FIELD => (net_approved_minutes / 60.0).round(2)
    }
  end

  def build_justification(review, integrity_check, total_approved_minutes, deducted_minutes)
    devlog_reviews = review.devlog_reviews.to_a
    total_original_minutes = devlog_reviews.sum { |dr| dr.original_minutes.to_i }
    ship_cert = review.effective_ship_cert
    project_id = review.project_id
    reviewer_name = review.reviewer&.display_name || review.reviewer&.email || "Unknown"

    # Format minutes
    original_formatted = format_minutes(total_original_minutes)
    approved_formatted = format_minutes(total_approved_minutes)
    adjusted_note = total_original_minutes == total_approved_minutes ? "" : " (This was adjusted to #{approved_formatted} after review.)"

    # Devlog tallies for the summary line
    approved_count = devlog_reviews.count(&:approved?)
    rejected_count = devlog_reviews.count(&:rejected?)
    approval_summary = "Of which #{approved_count} #{approved_count == 1 ? "was" : "were"} approved"
    approval_summary += " and #{rejected_count} rejected" if rejected_count.positive?

    # Per-devlog breakdown: minutes, status, and the reviewer's justification
    devlog_list = devlog_reviews.map do |dr|
      minutes = dr.approved_minutes || 0
      devlog_note = dr.justification.presence
      line = "devlog #{dr.post_devlog_id}: #{minutes} min #{dr.status}"
      line += ": \"#{devlog_note}\"" if devlog_note
      line
    end.join("\n")

    # A review counts as a project update when it carries an update description
    # or an earlier review of the same project exists (a reship).
    project_updated = review.project&.update_description.present? || prior_review?(review)

    intro = "The user logged #{original_formatted} on hackatime.#{adjusted_note}"
    intro += "\n#{commit_activity_sentence(review, total_original_minutes)}"
    intro += "\nThis is a project update." if project_updated
    if deducted_minutes.positive?
      deducted_hours = (deducted_minutes / 60.0).round(2)
      deduction_explanation = "Further deducted by #{deducted_hours} hours by the fraud department for hour fraud."
      deduction_explanation += " Reason: #{integrity_check.decision_justification}" if integrity_check.decision_justification.present?
      intro += "\n#{deduction_explanation}"
    end

    integrity_note = INTEGRITY_JUSTIFICATION_NOTES.fetch(integrity_check.status)

    # A project with no ship cert at all can't be linked — say so rather than
    # emitting a URL with an empty id, which reads as a broken review link.
    ship_cert_line = if ship_cert
      "The Ship Cert is at https://stardance.hackclub.com/admin/certification/ship/#{ship_cert.id}"
    else
      "No ship certification was issued for this project."
    end

    justification = <<~JUSTIFICATION
      #{intro}

      In this time they wrote #{devlog_reviews.count} devlogs. #{approval_summary}.

      This project was initially ship certified by #{ship_certifier_name(ship_cert)}.

      Following this it was YSWS reviewed by #{reviewer_name}

      #{devlog_list}
      ====================================================

      #{integrity_note}

      The Stardance project can be found at https://stardance.hackclub.com/projects/#{project_id}

      The Full YSWS Review + devlogs are at https://stardance.hackclub.com/admin/certification/review/#{review.id}

      #{ship_cert_line}
    JUSTIFICATION

    # Add shop orders section if available
    approved_orders = approved_orders_for(review.user)
    if approved_orders.any?
      manual_orders = approved_orders.reject { |order| order.fulfilled_by&.start_with?("System") }
      if manual_orders.any?
        orders_list = manual_orders.last(2).map do |order|
          item_name = order.shop_item.name
          fulfilled_by = order.fulfilled_by.presence || "Unknown"
          fulfilled_at = order.fulfilled_at&.strftime("%Y-%m-%d") || "Unknown date"
          "#{item_name} (x#{order.quantity}) - approved by #{fulfilled_by} on #{fulfilled_at}"
        end.join("\n")

        justification += "\n\nThis user has the following manually approved shop orders:\n#{orders_list}"
      end
    end

    # List the Hackatime project names linked to this project
    hackatime_project_names = review.project&.hackatime_projects&.distinct&.pluck(:name) || []
    justification += if hackatime_project_names.any?
      "\n\nUser's Hackatime Project Names: #{hackatime_project_names.join(", ")}"
    else
      "\n\nNo hackatime projects linked :cry:"
    end

    justification.strip
  end

  def approved_orders_for(user)
    user.shop_orders
      .where(aasm_state: "fulfilled")
      .where("fulfilled_by IS NULL OR fulfilled_by NOT LIKE ?", "System%")
      .includes(:shop_item)
  end

  def ship_certifier_name(ship_cert)
    ship_cert&.reviewer&.display_name || ship_cert&.reviewer&.email || "Unknown"
  end

  # Rates whole-project commit activity against total logged hours. Degrades to
  # an "unavailable" line instead of raising — git-host flakiness or a missing
  # repo URL shouldn't block the rewrite.
  def commit_activity_sentence(review, total_original_minutes)
    project = review.project
    provider = GitHost::Base.for(project&.repo_url)
    return "Commit activity could not be checked (no supported repo URL)." unless provider

    commit_count = provider.fetch_commits(
      since: project.created_at,
      before: review.post_ship_event&.created_at || Time.current
    ).size
    hours = total_original_minutes / 60.0
    return "They had #{commit_count} commits, but no logged hours to compare against." unless hours.positive?

    per_hour = commit_count / hours
    rating = per_hour > 1 ? "good" : per_hour > 0.8 ? "okay" : "BAD"

    "They had #{commit_count} commits, which compared to the original #{hours.round(1)} logged hours is \"#{rating}\" (#{per_hour.round(2)} commits/hour)."
  rescue StandardError => e
    Rails.logger.warn "#{LOG_PREFIX} commit activity check failed: #{e.class}: #{e.message}"
    "Commit activity could not be checked (fetch failed)."
  end

  def format_minutes(minutes)
    hours = minutes / 60
    remaining_minutes = minutes % 60
    hours > 0 ? "#{hours}h #{remaining_minutes}min" : "#{remaining_minutes}min"
  end

  # True when an earlier review exists for the same project (i.e. this is a
  # reship). Mirrors the prior-review lookup on the YSWS review page.
  def prior_review?(review)
    ::Certification::Ysws
      .where(project_id: review.project_id)
      .where("id < ?", review.id)
      .exists?
  end
end
