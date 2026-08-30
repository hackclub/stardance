# frozen_string_literal: true

class Shop::RefreshVerificationStatusJob < ApplicationJob
  queue_as :literally_whenever

  def perform
    user_ids = ShopOrder.where(aasm_state: "awaiting_verification")
                        .distinct.pluck(:user_id)

    User.where(id: user_ids)
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

    result = user.apply_hca_verification_payload!(payload, persist_with_callbacks: false)
    return if result == :invalid_status || result == :ignored_ineligible

    if user.eligible_for_shop?
      Shop::ProcessVerifiedOrdersJob.perform_later(user.id)
    end

  rescue StandardError => e
    Rails.logger.error "Failed to refresh verification status for user #{user.id}: #{e.message}"
    Sentry.capture_exception(e, extra: { user_id: user.id })
  end
end
