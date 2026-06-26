module User::Profile
  extend ActiveSupport::Concern

  GUEST_AVATAR_VARIANTS = %w[guest_star_1 guest_star_2 guest_star_3].freeze

  def full_name
    [ first_name, last_name ].compact.join(" ").strip
  end

  def avatar
    if slack_id.blank?
      variant = GUEST_AVATAR_VARIANTS[(id || 0) % GUEST_AVATAR_VARIANTS.size]
      ActionController::Base.helpers.image_path("avatars/#{variant}.png")
    else
      "https://cachet.dunkirk.sh/users/#{slack_id}/r"
    end
  end
end
