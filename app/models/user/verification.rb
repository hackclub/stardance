module User::Verification
  extend ActiveSupport::Concern

  included do
    after_commit :handle_verification_eligibility_change, if: :should_check_verification_eligibility?
  end

  def identity_verified? = verification_verified?
  def identity_submitted? = verification_verified? || verification_pending?

  def ysws_eligible?
    return manual_ysws_override if manual_ysws_override.in?([ true, false ])

    self[:ysws_eligible]
  end

  def eligible_for_shop? = identity_verified? && ysws_eligible?

  def should_reject_orders? = verification_ineligible? || (identity_verified? && !ysws_eligible?)

  def reject_awaiting_verification_orders!
    shop_orders.where(aasm_state: "awaiting_verification").find_each do |order|
      reason = if verification_ineligible?
                 "Identity verification marked as ineligible"
      else
                 "Not eligible for YSWS"
      end
      order.mark_rejected!(reason)
    end
  end

  def apply_hca_verification_payload!(payload, persist_with_callbacks: true)
    status = payload["verification_status"].to_s
    return :invalid_status unless self.class.verification_statuses.key?(status)

    # Record when we last pulled a status from HCA — drives the "last checked"
    # line on the verify popup — regardless of whether anything changed.
    update_columns(verification_checked_at: Time.current)

    fatal_rejection = payload["fatal_rejection"] == true
    return :ignored_ineligible if status == "ineligible" && !fatal_rejection

    fatal_ineligible = status == "ineligible" && fatal_rejection
    ysws_eligible = payload["ysws_eligible"] == true
    attrs = { verification_status: status, ysws_eligible: ysws_eligible }
    changed = attrs.any? { |key, value| self[key] != value }

    if changed
      if persist_with_callbacks
        update!(attrs)
      else
        update_columns(attrs.merge(updated_at: Time.current))
      end
    end

    enforce_fatal_rejection! if fatal_ineligible

    return :fatal_ineligible if fatal_ineligible
    return :updated if changed

    :unchanged
  end

  private

    def should_check_verification_eligibility?
      saved_change_to_verification_status? || saved_change_to_ysws_eligible?
    end

    def handle_verification_eligibility_change
      if eligible_for_shop?
        Shop::ProcessVerifiedOrdersJob.perform_later(id)
      elsif should_reject_orders?
        reject_awaiting_verification_orders!
      end
    end

    def enforce_fatal_rejection!
      reject_awaiting_verification_orders!
      return if banned?

      update_columns(
        banned: true,
        banned_at: Time.current,
        banned_reason: "Fatal identity verification rejection",
        updated_at: Time.current
      )
    end
end
