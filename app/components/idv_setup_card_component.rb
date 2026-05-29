# frozen_string_literal: true

# Body of the "verify your identity" popup (shared/_idv_verify_modal), opened
# from the IDV badge/alert when the user hasn't completed identity verification.
# Tone matches the link-account screen — reassure, explain why, and link to
# authoritative resources.
class IdvSetupCardComponent < ViewComponent::Base
  attr_reader :user, :return_to, :dom_id

  def initialize(user:, return_to: nil, dom_id: "idv-setup")
    @user = user
    @return_to = return_to
    @dom_id = dom_id
  end

  def render?
    user.present? && !user.identity_verified?
  end

  def status_eyebrow
    case user.verification_status
    when "pending"     then "we're reviewing"
    when "ineligible"  then "something went wrong"
    else                    "your work isn't public yet"
    end
  end

  def title
    case user.verification_status
    when "pending"     then "Hold tight — we're verifying your identity."
    when "ineligible"  then "We couldn't verify your identity."
    else                    "Verify your identity to share your work."
    end
  end

  def pending?     = user.verification_pending?
  def ineligible?  = user.verification_ineligible?

  def verify_url
    HCAService.verify_portal_url(return_to: return_to.presence || helpers.request.original_url)
  end
end
