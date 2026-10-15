module ExternalDashboard
  module BackfillRun
    extend self

    COUNTERS = %w[enqueued duplicate skipped failed].freeze
    OUTCOME_MAP = {
      duplicate: "duplicate",
      skipped: "skipped",
      not_configured: "skipped",
      client_error: "failed",
      failed: "failed"
    }.freeze
    TTL = 7.days

    def start(enqueued:)
      run_id = "#{Time.current.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(2)}"
      Rails.cache.increment(key(run_id, "enqueued"), enqueued, expires_in: TTL)
      run_id
    end

    def record(run_id, status)
      counter = OUTCOME_MAP[status&.to_sym]
      return if run_id.blank? || counter.nil?

      Rails.cache.increment(key(run_id, counter), 1, expires_in: TTL)
    end

    def record_enqueued(run_id)
      return if run_id.blank?

      Rails.cache.increment(key(run_id, "enqueued"), 1, expires_in: TTL)
    end

    def run_id_from(arguments)
      arguments.find { |arg| arg.is_a?(Hash) }&.dig(:backfill_run_id)
    end

    # Successful pushes are not counted (spares a cache hit per job on runs
    # that are mostly 200s) — ok is derived, so it's only exact once the
    # queue has drained; mid-run it still includes queued jobs.
    def report(run_id)
      counts = COUNTERS.index_with { |counter| Rails.cache.read(key(run_id, counter), raw: true).to_i }
      counts.symbolize_keys.merge(
        run_id: run_id,
        ok: counts["enqueued"] - counts.except("enqueued").values.sum
      )
    end

    private

    def key(run_id, counter)
      "external_dashboard:backfill:#{run_id}:#{counter}"
    end
  end
end
