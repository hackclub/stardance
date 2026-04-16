class FlushExtensionUsageJob < ApplicationJob
  BUFFER_KEY = "stardance:extension_usage_buffer"

  queue_as :default

  def perform
    return unless redis_available?

    batch_size = 1000

    Rails.cache.redis.with do |redis|
      loop do
        raw_items = redis.lrange(BUFFER_KEY, 0, batch_size - 1)
        break if raw_items.empty?

        redis.ltrim(BUFFER_KEY, raw_items.size, -1)

        records = raw_items.map do |raw|
          data = JSON.parse(raw)
          {
            project_id: data["project_id"],
            user_id: data["user_id"],
            recorded_at: data["recorded_at"],
            created_at: Time.current,
            updated_at: Time.current
          }
        end

        insert_batch(records)
      end
    end
  end

  private

  def insert_batch(records)
    return if records.empty?

    project_ids = records.map { |r| r[:project_id] }.uniq
    valid_project_ids = Project.where(id: project_ids).pluck(:id).to_set

    valid_records = records.select { |r| valid_project_ids.include?(r[:project_id]) }
    ExtensionUsage.insert_all(valid_records) if valid_records.any?
  end

  def redis_available?
    Rails.cache.respond_to?(:redis) && Rails.cache.redis.present?
  end
end
