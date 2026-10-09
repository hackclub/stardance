module Raffle
  module ApplicationHelper
    include ::ApplicationHelper

    # The AMD GPU raffle has ended. The dashboard hides the entry and referral
    # UI (free entry claim, referral link, fraud notice, leaderboard, verified
    # and pending referrals) and shows an ended notice instead; set this back
    # to false to bring that UI back unchanged.
    RAFFLE_ENDED = true

    def raffle_ended? = RAFFLE_ENDED

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
