module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      # Always-on: anonymous visitors must be able to open a cable connection
      # so they can subscribe to public Turbo Streams (e.g. the landing-page
      # RSVP counter). Per-user channels (NotificationsChannel) enforce auth
      # themselves by rejecting subscriptions when current_user is nil.
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      session_key = Rails.application.config.session_options[:key]
      user_id = cookies.encrypted[session_key]&.dig("user_id")
      return nil if user_id.blank?

      User.find_by(id: user_id)
    end
  end
end
