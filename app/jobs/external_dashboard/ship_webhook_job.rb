module ExternalDashboard
  class ShipWebhookJob < WebhookJob
    def perform(cert_id, backfill_run_id: nil)
      cert = Certification::Ship.find(cert_id)
      fill_proof_video_url(cert)
      result = ExternalDashboard::ShipWebhookService.call(cert, backfill: backfill_run_id.present?)
      BackfillRun.record(backfill_run_id, result.status)

      case result.status
      when :ok, :duplicate
        cert.assign_external_certification_id!(result.cert_id)
        chain_pending_return(cert, backfill_run_id)
        verb = result.status == :duplicate ? "already ingested" : "ingested"
        Rails.logger.info "[#{self.class.name}] cert=#{cert_id} #{verb} external_cert_id=#{result.cert_id}"
      when :not_configured, :skipped
        level = cert.pending? ? :info : :warn
        Rails.logger.public_send(level, "[#{self.class.name}] cert=#{cert_id} skipped (#{result.error})")
      when :client_error
        log_remote_failure("client error", cert_id, result)
      when :server_error
        raise_server_error(cert_id, result)
      end
    end

    private

      def fill_proof_video_url(cert)
        return unless cert.proof_video_url.blank? && cert.verdict_video.attached?

        url_options = Rails.application.config.action_controller.default_url_options || {}
        return if url_options[:host].blank?

        url = Rails.application.routes.url_helpers.rails_blob_url(cert.verdict_video, **url_options)
        cert.update!(proof_video_url: url)
      rescue StandardError => e
        Rails.logger.warn "[#{self.class.name}] cert=#{cert.id} proof_video_url fill failed: #{e.class}: #{e.message}"
      end

      def chain_pending_return(cert, backfill_run_id)
        active_return = cert.chain_pending_return
        return unless active_return

        BackfillRun.record_enqueued(backfill_run_id)
        ExternalDashboard::CertReturnJob.perform_later(active_return.id, backfill_run_id: backfill_run_id)
      end
  end
end
