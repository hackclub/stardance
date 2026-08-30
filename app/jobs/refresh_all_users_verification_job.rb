# frozen_string_literal: true

class RefreshAllUsersVerificationJob < ApplicationJob
  queue_as :literally_whenever

  def perform
    User.joins(:identities)
        .where(user_identities: { provider: "hack_club" })
        .where.not(user_identities: { access_token: [ nil, "" ] })
        .includes(:identities)
        .find_each do |user|
      refresh_verification_status(user)
    end
  end

  private

  def refresh_verification_status(user)
    identity = user.hack_club_identity
    return unless identity&.access_token.present?

    payload = HCAService.identity(identity.access_token)
    return if payload.blank?

    user.apply_hca_verification_payload!(payload, persist_with_callbacks: false)
  rescue StandardError => e
    Rails.logger.error "Failed to refresh verification status for user #{user.id}: #{e.message}"
    Sentry.capture_exception(e, extra: { user_id: user.id })
  end
end
