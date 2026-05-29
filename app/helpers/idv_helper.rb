# frozen_string_literal: true

module IdvHelper
  # Ported from Flavortown's HomeHelper#id_verification_ui_for — maps a user's
  # verification status to how the owner-facing IDV indicators present it.
  #
  # Statuses (User#verification_status enum): needs_submission, pending,
  # verified, ineligible (ineligible == rejected / poor quality).
  #
  # Returns nil when there's nothing to flag (no user, or already verified).
  #   state   – status symbol
  #   variant – :warning (pending / under review) or :danger (action needed)
  #   badge   – short status label
  #   line    – the owner-facing "why your stuff is private" sentence
  #   cta     – label for the link that opens the verify popup
  def idv_status_for(user)
    return nil if user.nil? || user.identity_verified?

    if user.verification_pending?
      { state: :pending, variant: :warning, badge: "Under review",
        line: "We're reviewing your identity — your profile stays private until it's approved.",
        cta: "Check status" }
    elsif user.verification_ineligible?
      { state: :ineligible, variant: :danger, badge: "Verification failed",
        line: "Your identity verification didn't go through, so your profile is private.",
        cta: "See what happened" }
    else # needs_submission
      { state: :needs_submission, variant: :danger, badge: "Not verified",
        line: "Your profile is private.",
        cta: "Verify your identity now" }
    end
  end
end
