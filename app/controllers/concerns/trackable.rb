module Trackable
  extend ActiveSupport::Concern

  private

  def track_event(name, properties = {})
    ahoy.track(name, properties)

    if current_user && Rails.application.credentials.dig(:fullstory, :api_key).present?
      TrackFullstoryEventJob.perform_later(user_id: current_user.id, name: name, properties: properties)
    end
  end
end
