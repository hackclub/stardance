class FlushExtensionUsageJob < ApplicationJob
  BUFFER_KEY = "stardance:extension_usage_buffer"
  BATCH_SIZE = 1000

  queue_as :latency_5m

  def perform
    return unless Rails.cache.respond_to?(:redis) && Rails.cache.redis.present?

    Rails.cache.redis.with do |redis|
      loop do
        raw_items = redis.lrange(BUFFER_KEY, 0, BATCH_SIZE - 1)
        break if raw_items.empty?

        redis.ltrim(BUFFER_KEY, raw_items.size, -1)

        project_ids = Set.new
        records = raw_items.filter_map do |raw|
          data = JSON.parse(raw)
          timestamp = data["recorded_at"]
          project_ids << data["project_id"]
          { project_id: data["project_id"], user_id: data["user_id"], created_at: timestamp, updated_at: timestamp }
        end

        project_ids &= Project.where(id: project_ids).ids
        records = records.select { |r| project_ids.include?(r[:project_id]) }

        ExtensionUsage.insert_all(records) if records.any?
      end
    end
  end
end
