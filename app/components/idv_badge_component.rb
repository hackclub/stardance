# frozen_string_literal: true

# Small `!` badge shown only to the owner on their own posts/profile when their
# identity isn't verified yet. The label is the hover text and explains that
# the surrounding content is hidden from other users until verification is
# done. Linking back to the profile IDV card means one place to act on it.
class IdvBadgeComponent < ViewComponent::Base
  attr_reader :user, :context

  CONTEXTS = %i[profile devlog post comment].freeze

  def initialize(user:, context: :devlog)
    @user = user
    @context = CONTEXTS.include?(context) ? context : :devlog
  end

  def render?
    user.present? && !user.identity_verified?
  end

  def tooltip
    case context
    when :profile
      "Only you and Hack Club admins can see your profile until you verify your identity."
    when :comment
      "Only you and Hack Club admins can see this comment until you verify your identity."
    when :post
      "Only you and Hack Club admins can see this post until you verify your identity."
    else
      "Only you and Hack Club admins can see this devlog until you verify your identity."
    end
  end

  def link_path
    helpers.user_path(user, anchor: "idv-setup")
  end
end
