# Thread-safe buffer for batching ActiveInsights records
# Instead of writing each request/job to the database immediately,
# we buffer them in memory and flush in batches via a background job.
class InsightsBuffer
  include Singleton

  MAX_BUFFER_SIZE = 500
  MAX_BUFFER_LIMIT = 5000  # Hard cap - drop oldest if exceeded to prevent memory issues
  FLUSH_INTERVAL_SECONDS = 30

  def initialize
    @request_buffer = []
    @job_buffer = []
    @mutex = Mutex.new
    @last_flush_at = Time.current
  end

  def push_request(attributes)
    should_flush = @mutex.synchronize do
      @request_buffer << attributes.merge(created_at: Time.current, updated_at: Time.current)
      trim_buffer_if_needed(@request_buffer)
      should_schedule_flush?
    end
    flush_async! if should_flush
  end

  def push_job(attributes)
    should_flush = @mutex.synchronize do
      @job_buffer << attributes.merge(created_at: Time.current, updated_at: Time.current)
      trim_buffer_if_needed(@job_buffer)
      should_schedule_flush?
    end
    flush_async! if should_flush
  end

  def flush!
    requests_to_insert = nil
    jobs_to_insert = nil

    @mutex.synchronize do
      requests_to_insert = @request_buffer.dup
      jobs_to_insert = @job_buffer.dup
      @request_buffer.clear
      @job_buffer.clear
      @last_flush_at = Time.current
    end

    insert_requests(requests_to_insert) if requests_to_insert.any?
    insert_jobs(jobs_to_insert) if jobs_to_insert.any?
  end

  def flush_async!
    Thread.new do
      Rails.application.executor.wrap { flush! }
    end
  end

  def buffer_size
    @mutex.synchronize { @request_buffer.size + @job_buffer.size }
  end

  def request_buffer_size
    @mutex.synchronize { @request_buffer.size }
  end

  def job_buffer_size
    @mutex.synchronize { @job_buffer.size }
  end

  private

  def should_schedule_flush?
    total_size = @request_buffer.size + @job_buffer.size
    time_since_last_flush = Time.current - @last_flush_at

    total_size >= MAX_BUFFER_SIZE || time_since_last_flush >= FLUSH_INTERVAL_SECONDS
  end

  def trim_buffer_if_needed(buffer)
    return unless buffer.size > MAX_BUFFER_LIMIT

    dropped = buffer.size - MAX_BUFFER_LIMIT
    buffer.shift(dropped)
    Rails.logger.warn "[InsightsBuffer] Dropped #{dropped} oldest records to stay under memory limit"
  end

  def insert_requests(records)
    return if records.empty?

    # Calculate duration for each record (mirrors ActiveInsights::Record before_validation)
    records.each do |record|
      if record[:started_at] && record[:finished_at]
        record[:duration] = (record[:finished_at] - record[:started_at]) * 1000
      end
    end

    ActiveInsights::Request.insert_all(records)
  rescue => e
    Rails.logger.error("[InsightsBuffer] Failed to batch insert requests: #{e.message}")
    Rails.error.report(e)
  end

  def insert_jobs(records)
    return if records.empty?

    # Calculate duration and queue_time for each record
    records.each do |record|
      if record[:started_at] && record[:finished_at]
        record[:duration] = (record[:finished_at] - record[:started_at]) * 1000
      end
      if record[:scheduled_at] && record[:started_at]
        record[:queue_time] = (record[:started_at] - record[:scheduled_at]) * 1000
      end
    end

    ActiveInsights::Job.insert_all(records)
  rescue => e
    Rails.logger.error("[InsightsBuffer] Failed to batch insert jobs: #{e.message}")
    Rails.error.report(e)
  end
end
