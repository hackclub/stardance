# frozen_string_literal: true

# Brings the virality reviews that were done in Airtable onto the platform.
#
# Reviews used to happen in the "_project_mentions" Airtable table, a copy of
# project_mentions with extra reviewer columns. Each row is matched to its
# mention by id and imported as follows:
#
# - internal notes, extra links, checklist, platform and metric are copied;
# - "on hold" rows are put on hold;
# - "approved" / "rejected" rows become a *proposed* verdict, with the reply
#   that was written in Airtable kept as the review note.
#
# Nothing is approved, rejected or paid by this job. Proposed verdicts appear
# under Reviewed in /admin/virality_reviews as "awaiting confirmation", and a
# reviewer confirms each one through the normal decision pipeline.
#
# Mentions the platform has already decided, or has any decision history for,
# are left alone. Every imported mention gets a "virality_airtable_import"
# audit entry.
#
# DRY RUN BY DEFAULT: logs and returns the summary and writes nothing.
#
# Usage:
#   OneTime::ImportAirtableViralityReviewsJob.perform_now                  # dry run
#   OneTime::ImportAirtableViralityReviewsJob.perform_now(dry_run: false)  # writes
class OneTime::ImportAirtableViralityReviewsJob < ApplicationJob
  queue_as :literally_whenever

  LOG_PREFIX = "[ImportAirtableViralityReviews]"
  TABLE_NAME = "_project_mentions"
  VERDICTS = { "approved" => "approve", "rejected" => "reject" }.freeze
  PLATFORMS = {
    "github" => "GitHub",
    "youtube" => "YouTube",
    "instagram" => "Instagram",
    "reddit" => "Reddit",
    "npm" => "Package manager",
    "modrinth" => "Modrinth / CurseForge",
    "curseforge" => "Modrinth / CurseForge",
    "x" => "Twitter / X"
  }.freeze

  def perform(dry_run: true)
    summary = rows.group_by { |row| import(row, dry_run: dry_run) }
      .transform_values { |imported| imported.map { |row| row["id"].to_i } }

    Rails.logger.info "#{LOG_PREFIX} #{'DRY RUN — ' if dry_run}#{summary.transform_values(&:size).inspect}"
    summary.slice(:unmatched, :invalid).each do |outcome, ids|
      Rails.logger.warn "#{LOG_PREFIX} #{outcome}: #{ids.inspect}"
    end
    summary
  end

  private

  def import(row, dry_run:)
    mention = ProjectMention.find_by(id: row["id"])
    return :unmatched unless mention && mention.project_id == row["project_id"].to_i
    return :already_reviewed if mention.status != :pending || mention.virality_decisions.exists?

    mention.assign_attributes(attributes_for(mention, row))
    return :unchanged unless mention.changed?
    return :invalid unless mention.valid?

    unless dry_run
      mention.paper_trail_event = "virality_airtable_import"
      mention.save!
    end
    if mention.proposed_action then :proposed
    elsif mention.on_hold_at then :held
    else :notes
    end
  end

  def attributes_for(mention, row)
    verdict = VERDICTS[row["review_status"]]
    {
      internal_notes: row["internal_notes"].presence || mention.internal_notes,
      extra_links: row["extra_links"].presence || mention.extra_links,
      review_checklist: (Array(row["review_checklist"]) & ProjectMention::ELIGIBILITY_CHECKS).presence || mention.review_checklist,
      reviewer_notes: row["reviewer_notes"].presence || mention.reviewer_notes,
      platform: platform_for(mention, row),
      metric_name: row["metric_name"].presence || mention.metric_name,
      metric_value: row["metric_value"]&.to_i || mention.metric_value,
      on_hold_at: (row["review_status"] == "on hold" ? mention.on_hold_at || Time.current : mention.on_hold_at),
      proposed_action: verdict,
      proposed_tier: (row["threshold"].to_s.downcase.presence_in(%w[good great]) if verdict == "approve")
    }
  end

  # Airtable platforms are free text; store the platform names the review
  # thresholds use.
  def platform_for(mention, row)
    recorded = row["platform"].to_s.downcase.presence
    Virality::Evidence.platform_for(mention.evidence_urls.first) || PLATFORMS[recorded] || (recorded ? "Other" : mention.platform)
  end

  def rows
    Norairrecord.table(
      Rails.application.credentials&.airtable&.api_key || ENV["AIRTABLE_API_KEY"],
      Rails.application.credentials&.airtable&.base_id || ENV["AIRTABLE_BASE_ID"],
      TABLE_NAME
    ).all.map(&:fields)
  end
end
