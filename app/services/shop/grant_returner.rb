module Shop
  class GrantReturner
    Result = Data.define(:returned, :message) do
      def returned? = returned
    end

    LOCK_TIMEOUT_SECONDS = 15

    NOT_RETURNABLE = "This order can't be returned.".freeze
    BUSY = "This grant is being updated right now. Try again in a moment.".freeze
    UNREACHABLE = "We couldn't reach HCB to check this grant. Try again in a moment.".freeze
    CLOSED = "This grant had been canceled on HCB, so it can't be returned.".freeze
    SPENT = "This grant has already been used, so it can't be returned.".freeze
    CANCEL_FAILED = "Something wrong happened, please ask in #stardance-help".freeze
    REFUND_FAILED = "Your grant was cancelled, but the stardust refund didn't go through, ask in #stardance-help".freeze

    attr_reader :order

    def initialize(order)
      @order = order
    end

    def call
      return failure(NOT_RETURNABLE) unless returnable_order?

      outcome = ShopCardGrant.with_advisory_lock(lock_key, timeout_seconds: LOCK_TIMEOUT_SECONDS) { return_grant }
      outcome || failure(BUSY)
    end

    private

    def grant = order.shop_card_grant

    def returnable_order?
      order.fulfilled? && order.grant? && grant&.hcb_grant_hashid.present?
    end

    def lock_key = "hcb_grant_fulfill_#{order.user_id}_#{order.shop_item_id}"

    def return_grant
      orders = grant.shop_orders.fulfilled.to_a
      return failure(NOT_RETURNABLE) unless orders.any? { |o| o.id == order.id }

      blocker = hcb_blocker
      return failure(blocker) if blocker
      return failure(CANCEL_FAILED) unless cancel_on_hcb

      refund(orders)
    end

    def hcb_blocker
      data = HCBService.show_card_grant(hashid: grant.hcb_grant_hashid)
      return UNREACHABLE if data.blank?
      return CLOSED unless data["status"].to_s == "active"
      return SPENT if ShopCardGrant.spent_grant?(data, expected_cents: grant.expected_amount_cents)

      nil
    rescue HCBError, Faraday::Error => e
      Rails.logger.error("GrantReturner lookup failed for ShopCardGrant ##{grant.id}: #{e.message}")
      UNREACHABLE
    end

    def cancel_on_hcb
      HCBService.cancel_card_grant!(hashid: grant.hcb_grant_hashid)
      true
    rescue HCBError, Faraday::Error => e
      Rails.logger.error("GrantReturner cancel failed for ShopCardGrant ##{grant.id}: #{e.message}")
      Sentry.capture_exception(e, extra: sentry_context)
      false
    end

    def refund(orders)
      ActiveRecord::Base.transaction { orders.each(&:refund!) }
      success(orders)
    rescue ActiveRecord::ActiveRecordError, AASM::InvalidTransition => e
      Rails.logger.error("GrantReturner refund failed after cancelling ShopCardGrant ##{grant.id}: #{e.message}")
      Sentry.capture_exception(e, level: :fatal, extra: sentry_context.merge(order_ids: orders.map(&:id)))
      failure(REFUND_FAILED)
    end

    def sentry_context
      { shop_card_grant_id: grant.id, hcb_grant_hashid: grant.hcb_grant_hashid, shop_order_id: order.id, user_id: order.user_id }
    end

    def success(orders)
      stardust = orders.sum { |o| o.total_cost_with_modifiers.to_i }
      message = "Grant returned. #{stardust} stardust is back in your balance."
      message += " This covered #{orders.size} orders on the same grant." if orders.size > 1
      Result.new(returned: true, message: message)
    end

    def failure(message) = Result.new(returned: false, message: message)
  end
end
