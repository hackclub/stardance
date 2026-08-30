# frozen_string_literal: true

# Runs the unattended fraud-review verdict for one order. Safe to retry and
# safe to run late: ShopOrder#auto_approvable? re-checks every condition,
# including that the order is still awaiting review.
class Shop::AutoApproveJob < ApplicationJob
  queue_as :latency_5m

  # Fulfilment reaches HCB, which goes down and loses its authorization from
  # time to time, so a failure is backed off rather than abandoned. Retrying is
  # safe because Shop::HCBGrantFulfillable records the disbursement against the
  # order before marking it fulfilled, so a second attempt finishes the
  # bookkeeping instead of granting again. Once the attempts are spent the
  # order simply stays in the queue for a person, with the failure on record.
  retry_on Shop::AutoApprovable::FulfilmentFailed,
           wait: :polynomially_longer,
           attempts: 5 do |job, error|
    order = job.arguments.first
    Rails.logger.error "[Shop::AutoApproveJob] giving up on order=#{order.id}: #{error.message}"
    Sentry.capture_exception(error, extra: { shop_order_id: order.id, source: "auto_approve" })
    order.record_auto_approval_failure(error)
  end

  def perform(shop_order)
    shop_order.auto_approve!
  end
end
