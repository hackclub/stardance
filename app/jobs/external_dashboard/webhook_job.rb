module ExternalDashboard
  class WebhookJob < ::ApplicationJob
    class RetriableServerError < StandardError; end

    queue_as :latency_5m

    self.enqueue_after_transaction_commit = true

    discard_on ActiveRecord::RecordNotFound do |job, _error|
      BackfillRun.record(BackfillRun.run_id_from(job.arguments), :skipped)
    end

    retry_on Faraday::Error, RetriableServerError, wait: :polynomially_longer, attempts: 4 do |job, error|
      cert_id = job.arguments.first
      BackfillRun.record(BackfillRun.run_id_from(job.arguments), :failed)
      Rails.logger.warn "[#{job.class.name}] cert=#{cert_id} giving up after #{error.class}: #{error.message}"
      Sentry.capture_message(
        "ExternalDashboard webhook gave up after retries",
        level: :warning,
        extra: {
          job_class: job.class.name,
          cert_id: cert_id,
          error_class: error.class.name,
          error_message: error.message.to_s.truncate(ExternalDashboard::Client::ERROR_MESSAGE_MAX)
        }
      )
    end

    private

      def log_remote_failure(label, cert_id, result)
        Rails.logger.warn "[#{self.class.name}] cert=#{cert_id} #{label} http=#{result.http_status} error=#{result.error}"
        Sentry.capture_message(
          "ExternalDashboard webhook #{label}",
          level: :warning,
          extra: {
            job_class: self.class.name,
            cert_id: cert_id,
            http_status: result.http_status,
            error: result.error
          }
        )
      end

      def raise_server_error(cert_id, result)
        raise RetriableServerError, "cert=#{cert_id} http=#{result.http_status} error=#{result.error}"
      end
  end
end
