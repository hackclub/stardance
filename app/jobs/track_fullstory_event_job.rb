class TrackFullstoryEventJob < ApplicationJob
  queue_as :default

  def perform(user_id:, name:, properties:)
    api_key = Rails.application.credentials.dig(:fullstory, :api_key)
    return if api_key.blank?

    uri = URI("https://api.fullstory.com/v2/events")
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Basic #{api_key}"
    req["Content-Type"] = "application/json"
    req.body = {
      name: name,
      properties: properties,
      context: { user: { uid: user_id.to_s } },
      session: { use_most_recent: true }
    }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
      http.request(req)
    end

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("FullStory event API returned #{response.code}: #{response.body.to_s.truncate(200)}")
    end
  end
end
