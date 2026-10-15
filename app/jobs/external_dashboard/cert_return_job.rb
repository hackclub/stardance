module ExternalDashboard
  class CertReturnJob < WebhookJob
    def perform(cert_id, backfill_run_id: nil)
      cert = Certification::Ship.find(cert_id)
      result = ExternalDashboard::CertReturnService.call(cert)

      case result.status
      when :ok
        Rails.logger.info "[#{self.class.name}] cert=#{cert_id} returned external_cert_id=#{cert.external_certification_id}"
      when :not_configured, :skipped
        BackfillRun.record(backfill_run_id, :skipped)
        Rails.logger.info "[#{self.class.name}] cert=#{cert_id} skipped (#{result.error})"
      when :client_error
        if result.error.to_s.match?(/only approved/i)
          BackfillRun.record(backfill_run_id, :duplicate)
          Rails.logger.info "[#{self.class.name}] cert=#{cert_id} already returned remotely (#{result.error})"
        else
          BackfillRun.record(backfill_run_id, :failed)
          log_remote_failure("client error", cert_id, result)
        end
      when :server_error
        raise_server_error(cert_id, result)
      end
    end
  end
end
