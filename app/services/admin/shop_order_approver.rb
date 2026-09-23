module Admin
  class ShopOrderApprover
    Result = Struct.new(:order, :approved, :message, keyword_init: true) do
      def approved? = approved
    end

    def initialize(order, actor:, tracking_number: nil)
      @order = order
      @actor = actor
      @tracking_number = tracking_number.presence
    end

    def call
      return failure("You cannot approve your own order.") if order.user_id == actor.id
      return failure("This order has already been processed.") unless order.pending? || order.awaiting_verification_call?
      if order.requires_additional_review?(ShopOrderReview::APPROVE)
        return failure("This is a high-value order and requires #{ShopOrderReview::REQUIRED_COUNT} fraud dept approvals before it can be approved " \
                       "(#{order.review_count(ShopOrderReview::APPROVE)}/#{ShopOrderReview::REQUIRED_COUNT} so far).")
      end

      return fulfill_immediately if order.shop_item.respond_to?(:fulfill!)

      queue_for_next_step
    end

    private

    attr_reader :order, :actor, :tracking_number

    # Rescues StandardError rather than HCBError alone: fulfilment also raises
    # plain errors (a cancelled grant, a failed save), and those used to reach
    # the reviewer as a 500 instead of a message they could act on.
    def fulfill_immediately
      order.approve!
      success("Order ##{order.id} approved and fulfilled")
    rescue StandardError => e
      Rails.logger.error "Fulfillment failed for order #{order.id}: #{e.message}"
      Sentry.capture_exception(e, extra: { shop_order_id: order.id })
      failure("Fulfillment failed (#{e.message}). The order was not approved and nothing was charged. " \
              "If this is an HCB grant, an administrator may need to re-authenticate the HCB integration before retrying.")
    end

    def queue_for_next_step
      if order.shop_item.requires_verification_call?
        moved = order.queue_for_verification_call && order.save
        message = "Order ##{order.id} queued for verification call"
      else
        order.tracking_number = tracking_number if tracking_number
        moved = order.queue_for_fulfillment && order.save
        message = "Order ##{order.id} approved for fulfillment"
      end

      return failure("Failed to approve order: #{order.errors.full_messages.join(', ')}") unless moved

      success(message)
    end

    def success(message) = Result.new(order: order, approved: true, message: message)

    def failure(message) = Result.new(order: order, approved: false, message: message)
  end
end
