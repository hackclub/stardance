# frozen_string_literal: true

class My::VerificationsController < ApplicationController
  # User-initiated "check my verification status" — re-pulls the latest from
  # Hack Club Auth and applies it (same effect as the portal-return refresh),
  # so a pending user can self-check without re-logging in or waiting for the
  # background sweep.
  def refresh
    return head :unauthorized unless current_user

    identity = current_user.hack_club_identity
    if identity&.access_token.present?
      payload = HCAService.identity(identity.access_token)
      current_user.apply_hca_verification_payload!(payload) if payload.present?
    end

    redirect_back fallback_location: user_path(current_user), notice: status_message
  rescue StandardError => e
    Rails.logger.warn("Verification refresh failed: #{e.class}: #{e.message}")
    Sentry.capture_exception(e, extra: { user_id: current_user&.id })
    redirect_back fallback_location: user_path(current_user),
                  alert: "Couldn't check your verification status right now — try again in a moment."
  end

  private

  def status_message
    current_user.reload
    if current_user.identity_verified?
      "You're verified — your work is now public."
    elsif current_user.verification_pending?
      "Still under review. We'll update this the moment Hack Club approves it."
    elsif current_user.verification_ineligible?
      "Your identity verification didn't go through. Open it to see what to do next."
    else
      "You haven't verified your identity yet."
    end
  end
end
