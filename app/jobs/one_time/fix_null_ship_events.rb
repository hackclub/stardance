class OneTime::FixNullShipEvents < ApplicationJob
  queue_as :literally_whenever

  NOTIFY_USER_ID = "U05F4B48GBF"

  def perform(dry_run: true)
    deleted = 0
    migrated = 0

    Post::ShipEvent.where(hours: nil).find_each do |ship_event|
      project = ship_event.project
      calculated_hours = project ? ship_event.hours : nil
      log_prefix = "[FixNullShipEvents]#{" (DRY RUN)" if dry_run} ShipEvent ##{ship_event.id}"

      if project.nil? || calculated_hours <= 0
        reason = project.nil? ? "no project" : "0 hours (#{project_url(project)})"
        Rails.logger.warn "#{log_prefix} deleting: #{reason}"
        next if dry_run

        ship_event_id = ship_event.id
        Vote.where(ship_event_id: ship_event_id).delete_all
        ship_event.reload.destroy
        notify_admin("ShipEvent ##{ship_event_id} deleted: #{reason}.")
        deleted += 1
        next
      end

      next if dry_run

      if ship_event.legacy_voting_scale? && ship_event.certification_status == "approved" && ship_event.payout.blank?
        vote_count = ship_event.votes.count
        clear_legacy_votes!(ship_event)
        migrated += 1
        Rails.logger.info "#{log_prefix} migrated to current voting scale (#{vote_count} votes cleared)"
      end
    end

    Rails.logger.info "[FixNullShipEvents]#{" (DRY RUN)" if dry_run} done — #{deleted} deleted, #{migrated} migrated to current scale"
    ShipEventMajorityJudgmentRefreshJob.perform_later if migrated > 0
  end

  private

  def project_url(project)
    "https://stardance.hackclub.com/projects/#{project.id}"
  end

  def notify_admin(message)
    SendSlackDmJob.perform_later(NOTIFY_USER_ID, message)
  end

  # wipes legacy-scale votes if any and bumps to current scale so voting can run normally.
  def clear_legacy_votes!(ship_event)
    ActiveRecord::Base.transaction do
      user_ids = ship_event.votes.distinct.pluck(:user_id)
      ship_event.votes.delete_all
      Post::ShipEvent.reset_counters(ship_event.id, :votes)
      user_ids.each { |uid| User.reset_counters(uid, :votes) }
      ship_event.update_column(:voting_scale_version, Post::ShipEvent::CURRENT_VOTING_SCALE_VERSION)
    end
  end
end
