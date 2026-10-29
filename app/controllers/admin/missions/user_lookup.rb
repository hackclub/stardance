module Admin
  module Missions
    # Finds the user an admin typed into a mission sub-resource form.
    module UserLookup
      private

      # Accepts an email, a username (with or without "@", or a profile URL),
      # a numeric user ID, or a Slack ID.
      def find_user(query)
        return if query.blank? || query.length > 320
        return User.find_by("LOWER(email) = ?", query.downcase) if email_like?(query)

        handle = query.sub(%r{\Ahttps?://[^/]+/}, "").delete_prefix("@")
        (User.find_by(id: query) if query.match?(/\A\d+\z/)) ||
          User.find_by(slack_id: query) ||
          User.find_by("LOWER(display_name) = ?", handle.downcase)
      end

      # Plain string checks rather than a regex: an email has one "@" that
      # isn't leading (that's "@username") and no "/" (that's a profile URL).
      # The database lookup is what decides whether it really matches.
      def email_like?(query)
        query.count("@") == 1 && !query.start_with?("@") && !query.include?("/")
      end
    end
  end
end
