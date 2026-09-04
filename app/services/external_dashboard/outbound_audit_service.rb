module ExternalDashboard
  # Heals UUIDs directly from a wide /ships pull, then hands off to
  # ShipBackfillService for whatever's still missing (which also covers
  # missed YSWS returns - it already retries those unconditionally).
  class OutboundAuditService
    WINDOW = 7.days

    def self.call(...) = new(...).call

    def initialize(window: WINDOW, now: Time.current)
      @window = window
      @now = now
    end

    def call
      result = ShipsClient.fetch_all(updated_since: now - window, status: "all")
      alert_on_unhealthy_fetch(result) unless result.status == :ok
      return { fetch_status: result.status, healed: 0, backfill: nil } if result.status == :not_configured

      healed = heal_missing_uuids(result.ships)
      backfill = ShipBackfillService.call

      Rails.logger.info "[ExternalDashboard::OutboundAuditService] fetch=#{result.status} fetched=#{result.ships.size} healed=#{healed} backfill_run=#{backfill.run_id}"
      { fetch_status: result.status, healed: healed, backfill: backfill }
    end

    private

    attr_reader :window, :now

    def alert_on_unhealthy_fetch(result)
      Sentry.capture_message(
        "ExternalDashboard::OutboundAuditService fetch did not complete",
        level: :warning,
        extra: { fetch_status: result.status, fetch_error: result.error, fetched: result.ships.size }
      )
    end

    def heal_missing_uuids(ships)
      by_external_id = ships.index_by { |ship| ship["externalId"].to_s }
      healed = 0

      Certification::Ship.where(external_certification_id: nil).includes(:project, :project_with_deleted).find_each do |cert|
        row = by_external_id[cert.id.to_s]
        next unless row
        next if cert.project&.hardware?
        next unless matches_project_name?(cert, row)
        next unless cert.assign_external_certification_id!(row["id"]) == :persisted

        healed += 1
        chain_pending_return(cert)
      end

      healed
    end

    def chain_pending_return(cert)
      active_return = cert.chain_pending_return
      return unless active_return

      ExternalDashboard::CertReturnJob.perform_later(active_return.id)
    end

    def matches_project_name?(cert, row)
      remote_name = row.dig("project", "name").to_s.presence
      remote_name.present? && remote_name == cert.project&.title
    end
  end
end
