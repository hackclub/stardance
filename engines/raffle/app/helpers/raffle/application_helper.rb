module Raffle
  module ApplicationHelper
    include ::ApplicationHelper
    def referral_display_name(user)
      return "A new participant" unless user

      user.display_name.presence || "A new participant"
    end

    def participant_avatar_url(participant)
      return if participant.nil?

      user = participant.user
      if user.respond_to?(:avatar_url) && user.avatar_url.present?
        user.avatar_url
      else
        asset_path("avatars/guest_star_#{(participant.id % 3) + 1}.png")
      end
    end
  end
end
