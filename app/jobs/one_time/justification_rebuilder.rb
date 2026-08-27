# frozen_string_literal: true

# The override-hours justification text, rebuilt from current Stardance data.
#
# This is a copy of Certification::YswsAirtableSyncJob's builder rather than an
# extraction from it: the sync job writes the text once, at review completion,
# and is free to evolve. The one-time cleanup jobs that rewrite already-synced
# rows share this copy so a rewritten row reads exactly like one the completion
# sync wrote today, and so the copy exists once rather than once per cleanup.
#
# Including classes must define a LOG_PREFIX constant.
module OneTime::JustificationRebuilder
  # One line per Certification::Integrity status, embedded in the justification.
  # Uses fetch so an unmapped new status fails loudly.
  INTEGRITY_JUSTIFICATION_NOTES = {
    "auto_passed" => "Passed automatic heartbeat checks.",
    "pending" => "Waiting for manual heartbeat review.",
    "manually_passed" => "Passed manual heartbeat review.",
    "deducted" => "Hours deducted during manual review.",
    "banned" => "Project rejected due to manual review of heartbeats."
  }.freeze

  private

  # The two fields the completion sync derives from the integrity verdict. A
  # deduction comes off the reviewer-approved total before the hours are
  # reported, so both move together. Hardware projects carry no integrity check
  # and so never have a deduction.
  def build_fields(review, integrity_check)
    total_approved_minutes = review.approved_minutes_total
    deducted_minutes = integrity_check&.deducted? ? integrity_check.deduction_minutes.to_i : 0
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
    Rails.logger.warn "#{self.class::LOG_PREFIX} commit activity check failed: #{e.class}: #{e.message}"
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
