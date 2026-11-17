# frozen_string_literal: true

# Sends every approved hardware build that never reached Airtable through
# Certification::HardwareBuildAirtableSyncJob.
#
# Builds approved before that job existed only got a YSWS review, and hardware
# reviews are left out of the YSWS queue, so they sat pending and never synced.
# A build whose YSWS review was completed by hand already synced and is skipped.
#
# DRY RUN BY DEFAULT: logs and returns the candidates, enqueues nothing.
#
# Usage:
#   OneTime::BackfillHardwareBuildAirtableJob.perform_now                  # dry run
#   OneTime::BackfillHardwareBuildAirtableJob.perform_now(dry_run: false)  # enqueues
class OneTime::BackfillHardwareBuildAirtableJob < ApplicationJob
  queue_as :literally_whenever

  LOG_PREFIX = "[BackfillHardwareBuildAirtable]"

  Result = Struct.new(:enqueued, :missing_cert, keyword_init: true)

  def scope
    ::Certification::Ysws
      .pending
      .joins(:project, :post_ship_event)
      .merge(::Project.hardware)
      .where(post_ship_events: { certification_status: "approved" })
  end

  def perform(dry_run: true)
    pairs = []
    missing_cert = []

    scope.find_each do |review|
      cert = review.effective_ship_cert
      if cert&.approved?
        pairs << [ cert.id, review.post_ship_event_id ]
      else
        missing_cert << review.id
      end
    end

    if missing_cert.any?
      Rails.logger.warn "#{LOG_PREFIX} #{missing_cert.size} review(s) with no approved ship cert, skipped: #{missing_cert.inspect}"
    end

    if dry_run
      Rails.logger.info "#{LOG_PREFIX} DRY RUN, would enqueue #{pairs.size} sync(s) [ship_cert_id, ship_event_id]: #{pairs.inspect}"
      return Result.new(enqueued: pairs, missing_cert: missing_cert)
    end

    pairs.each { |cert_id, ship_event_id| ::Certification::HardwareBuildAirtableSyncJob.perform_later(cert_id, ship_event_id) }
    Rails.logger.info "#{LOG_PREFIX} Enqueued #{pairs.size} sync(s)"

    Result.new(enqueued: pairs, missing_cert: missing_cert)
  end
end
