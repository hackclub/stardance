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
  queue_as :literally_whenever

  LOG_PREFIX = "[RefreshUnsubmittedYswsJustification]"

  JUSTIFICATION_FIELD = "Optional - Override Hours Spent Justification"
  REVIEW_ID_FIELD = "review_id"
  # Populated by the Unified YSWS base's automation once it picks a row up.
  UNIFIED_RECORD_ID_FIELD = "Automation - YSWS Record ID"

  # One line per Certification::Integrity status, embedded in the justification.
  # Uses fetch so an unmapped new status fails loudly.
  INTEGRITY_JUSTIFICATION_NOTES = {
    "auto_passed" => "Passed automatic heartbeat checks.",
    "pending" => "Waiting for manual heartbeat review.",
    "manually_passed" => "Passed manual heartbeat review.",
    "deducted" => "Hours deducted during manual review.",
    "banned" => "Project rejected due to manual review of heartbeats."
  }.freeze

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

  # ---- Copied from Certification::YswsAirtableSyncJob ---------------------
  # Kept verbatim (minus the argument threading) so a rewritten row is
  # indistinguishable from one the completion sync wrote today. This job is a
  # one-time cleanup and gets deleted, so the two are allowed to drift.

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

    integrity_note = integrity_check ? INTEGRITY_JUSTIFICATION_NOTES.fetch(integrity_check.status) : "Hardware project — integrity check not applicable."

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

    # Identify the Hackatime account behind the hours so reviewers can look it
    # up directly, then list the project names linked to this project.
    hackatime_uid = review.user&.hackatime_identity&.uid
    justification += "\n\nUser's Hackatime ID: #{hackatime_uid.presence || "none linked"}"

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
