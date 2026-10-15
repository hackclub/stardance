# frozen_string_literal: true

class OneTime::BackfillFraudIntegrityJob < ApplicationJob
  queue_as :literally_whenever

  # Ship events with a completed YSWS review (reviewed_at present) but no
  # integrity outcome yet. The join is on the ship event:
  # certification_ysws_reviews.post_ship_event_id and
  # certification_integrities.ship_event_id both reference post_ship_events.id;
  # where.missing(:integrity_check) selects the ones without an integrity.
  def scope
    Post::ShipEvent
      .where(id: Certification::Ysws.select(:post_ship_event_id))
      .where.missing(:integrity_check)
  end

  def perform
    count = 0

    scope.find_each do |ship_event|
      Certification::Fraud::AutoDetectionJob.perform_later(ship_event)
      count += 1
    end

    Rails.logger.info "[OneTime::BackfillFraudIntegrity] Enqueued #{count} auto-detection jobs"
    count
  end
end
