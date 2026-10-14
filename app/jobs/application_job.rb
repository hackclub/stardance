class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked
  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # Helper method to add retry logic with maintainer notification on max retries
  # Use this in recurring jobs: notify_maintainers_on_exhaustion StandardError, maintainers_slack_ids: ["U123", "U456"], wait: :polynomially_longer, attempts: 3
  class << self
    def notify_maintainers_on_exhaustion(exception_class, maintainers_slack_ids:, wait: :polynomially_longer, attempts: 3)
      retry_on exception_class, wait: wait, attempts: attempts do |job, exception|
        notify_maintainers_of_job_failure(job, exception, maintainers_slack_ids)
      end
    end

    private

    def notify_maintainers_of_job_failure(job, exception, maintainers_slack_ids)
      if Rails.env.development?
        Rails.logger.error(
          "🚨 Job Failure Alert: #{job.class.name} (#{job.job_id})\n" \
          "Error: #{exception.message}\n" \
          "Arguments: #{job.arguments.inspect}\n" \
          "Maintainers: #{maintainers_slack_ids.join(", ")}"
        )
      else
        maintainers_slack_ids.each do |slack_id|
          next unless slack_id.present?

             SendSlackDmJob.perform_later(
            slack_id,
            nil,
            blocks_path: "notifications/job_failure_alert",
            locals: {
              job_class: job.class.name,
              error_message: exception.message,
              error_backtrace: exception.backtrace&.first(5),
              job_arguments: job.arguments,
              job_id: job.job_id,
              executions_count: job.executions
            }
          )
        end
      end

      raise exception
    end
  end
end
