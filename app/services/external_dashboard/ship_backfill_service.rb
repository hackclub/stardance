module ExternalDashboard
  class ShipBackfillService
    DEFAULT_RATE_PER_SECOND = 2

    Result = Struct.new(:status, :run_id, :enqueued, :error, keyword_init: true)

    def self.call(scope: nil, rate_per_second: DEFAULT_RATE_PER_SECOND)
      return Result.new(status: :not_configured, enqueued: 0, error: Client::NOT_CONFIGURED_ERROR) unless Client.configured?

      hw_project_ids = hardware_project_ids
      active_returns = Certification::Ship.pending.where.not(returned_by_id: nil).where.not(project_id: hw_project_ids)
      scope ||= Certification::Ship.where(external_certification_id: nil).where.not(project_id: hw_project_ids).where.not(id: active_returns.select(:id))
      link_ship_events(scope)
      cert_ids = scope.pluck(:id)
      return_ids = active_returns.where.not(external_certification_id: nil).pluck(:id)
      # A return whose UUID never got handed over lands in neither list above, so it used
      # to sit here forever. Push the approved cert still holding that UUID instead and
      # ShipWebhookJob chains the return off it.
      chain_ids = stranded_return_predecessors(active_returns, hw_project_ids)
      run_id = BackfillRun.start(enqueued: cert_ids.size + return_ids.size + chain_ids.size)

      (cert_ids + chain_ids).each_with_index do |cert_id, index|
        delay = (index.to_f / rate_per_second).seconds
        ExternalDashboard::ShipWebhookJob.set(wait: delay).perform_later(cert_id, backfill_run_id: run_id)
      end

      return_ids.each { |cert_id| ExternalDashboard::CertReturnJob.perform_later(cert_id, backfill_run_id: run_id) }

      Rails.logger.info "[ExternalDashboard::ShipBackfillService] run=#{run_id} enqueued=#{cert_ids.size} chained=#{chain_ids.size} returns=#{return_ids.size} rate=#{rate_per_second}/s"
      Result.new(status: :ok, run_id: run_id, enqueued: cert_ids.size + return_ids.size + chain_ids.size)
    end

    def self.report(run_id)
      BackfillRun.report(run_id)
    end

    # update_all on purpose: bulk console wipe of a side-band identifier,
    # skipping per-row callbacks/validations/PaperTrail.
    def self.reset_external_ids!
      cleared = Certification::Ship.where.not(external_certification_id: nil).update_all(external_certification_id: nil)
      Rails.logger.info "[ExternalDashboard::ShipBackfillService] cleared external ids from #{cleared} certs"
      cleared
    end

    def self.clean_backfill!(rate_per_second: DEFAULT_RATE_PER_SECOND)
      reset_external_ids!
      call(rate_per_second: rate_per_second)
    end

    def self.hardware_project_ids
      Project.unscoped.where.not(hardware_stage: nil).pluck(:id)
    end
    private_class_method :hardware_project_ids

    def self.stranded_return_predecessors(active_returns, hw_project_ids)
      events = active_returns.where(external_certification_id: nil)
                             .where.not(post_ship_event_id: nil)
                             .select(:post_ship_event_id)

      Certification::Ship.approved
                         .where.not(external_certification_id: nil)
                         .where.not(project_id: hw_project_ids)
                         .where(post_ship_event_id: events)
                         .pluck(:id)
    end
    private_class_method :stranded_return_predecessors

    def self.link_ship_events(scope)
      linked = 0
      scope.where(post_ship_event_id: nil).find_each do |cert|
        event = cert.project&.ship_events
                    &.where(post_ship_events: { created_at: ..cert.created_at })
                    &.order("post_ship_events.created_at DESC")
                    &.first
        next unless event

        cert.update!(post_ship_event_id: event.id)
        linked += 1
      end
      Rails.logger.info "[ExternalDashboard::ShipBackfillService] linked=#{linked} ship events" if linked.positive?
    end
  end
end
