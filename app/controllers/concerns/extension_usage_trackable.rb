module ExtensionUsageTrackable
  extend ActiveSupport::Concern

  included do
    after_action :track_extension_usage
  end

  private

  def track_extension_usage
    project_id = request.headers["X-Stardance-Project-Id"]
    return unless project_id.present?

    tracking_user = try(:current_api_user) || try(:current_user)
    return unless tracking_user

    return unless Rails.cache.respond_to?(:redis) && Rails.cache.redis.present?

    payload = { project_id: project_id.to_i, user_id: tracking_user.id, recorded_at: Time.current.iso8601 }.to_json
    Rails.cache.redis.with { |redis| redis.lpush(FlushExtensionUsageJob::BUFFER_KEY, payload) }
  rescue StandardError => e
    Rails.logger.warn("Extension usage tracking failed: #{e.class}: #{e.message}")
  end
end
