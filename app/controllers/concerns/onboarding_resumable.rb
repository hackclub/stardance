# Shared logic for resuming or expiring an interrupted signup-wizard session.
#
# A "mid-onboarding" user is one who has never completed onboarding
# (onboarded_at still nil) — regardless of whether they entered via the email
# flow (guest) or directly through HCA. The freshness window is anchored on
# when they started (created_at).
#
# Gated on the :new_onboarding flag.
module OnboardingResumable
  extend ActiveSupport::Concern

  ONBOARDING_WINDOW = 7.days

  private

  def resume_or_expire_onboarding!
    user = current_user
    return unless onboarding_in_progress?(user)

    if onboarding_fresh?(user)
      redirect_to onboarding_resume_path(user)
    else
      reset_session
      redirect_to root_path
    end
  end

  def onboarding_in_progress?(user)
    return false unless Flipper.enabled?(:new_onboarding)

    user.present? && user.onboarded_at.nil?
  end

  # Within the active window, anchored on when they first started onboarding.
  def onboarding_fresh?(user)
    user.created_at >= ONBOARDING_WINDOW.ago
  end

  # The first wizard step the user hasn't answered yet.
  def onboarding_resume_path(user)
    return onboarding_age_gate_path   if user.age_blocked?
    return onboarding_birthday_path   if user.age_attestation.blank?
    return onboarding_experience_path if user.experience_level.blank?
    return onboarding_interests_path  if user.interests.blank?

    onboarding_name_path
  end

  # Wipe wizard answers so the flow starts over from the top. The email and
  # placeholder name are kept (email is unique, and the name is still a
  # placeholder because they never finished the name step).
  def restart_onboarding!(user)
    user.update!(
      age_attestation: nil,
      experience_level: nil,
      interests: [],
      onboarded_at: nil
    )
  end
end
