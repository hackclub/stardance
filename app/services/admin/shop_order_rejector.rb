module Admin
  class ShopOrderRejector
    # `review` is set when the submission recorded a vote towards a high-value
    # order's second rejection instead of rejecting it outright.
    Result = Data.define(:order, :rejected, :message, :review) do
      def rejected? = rejected
    end

    # A rejection has to name a project even when it carries no fraud finding,
    # so the ones that do not point at the Stardance project itself.
    PLACEHOLDER_FRAUD_PROJECT_ID = 1

    # Whose rejection carries fraud metadata: a fraud dept member rejecting an
    # order that is actually sitting in fraud review. An admin rejecting for
    # fulfillment reasons, or a fraud dept member rejecting an order that
    # already moved past fraud review, falls back to the buyer-facing reason,
    # so their forms must not ask for the internal fields. Any form collecting
    # them has to gate on this, or the model's presence validations reject a
    # submission whose fields were never rendered.
    def self.records_fraud_details?(order, actor) = actor.fraud_dept? && order.fraud_review_state?

    def initialize(order, actor:, reason: nil, internal_reason: nil, joe_case_url: nil, fraud_project_id: nil)
      @order = order
      @actor = actor
      @reason = reason.presence || "No reason provided"
      fraud_reviewer = self.class.records_fraud_details?(order, actor)
      @internal_reason = fraud_reviewer ? internal_reason.presence : @reason
      @joe_case_url = fraud_reviewer ? joe_case_url.presence : nil
      @fraud_project_id = fraud_reviewer ? fraud_project_id.presence : PLACEHOLDER_FRAUD_PROJECT_ID
    end

    def call
      vote = record_rejection_vote
      return vote if vote

      old_state = order.aasm_state
      order.internal_rejection_reason = internal_reason
      order.joe_case_url = joe_case_url
      order.fraud_related_project_id = fraud_project_id

      return failure("Failed to reject order: #{order.errors.full_messages.join(', ')}") unless order.mark_rejected(reason) && order.save

      record_version(order, old_state)
      accessory_count = reject_accessories
      message = "Order ##{order.id} rejected"
      message += " (#{accessory_count} #{'accessory'.pluralize(accessory_count)} also rejected)" if accessory_count.positive?
      success(message)
    end

    private

    attr_reader :order, :actor, :reason, :internal_reason, :joe_case_url, :fraud_project_id

    # A high-value order needs two reviewers to agree before it is rejected, so
    # the first submission records a vote and the second one, holding the same
    # form, rejects for real. Returns nil once the order can be rejected.
    def record_rejection_vote
      return nil unless order.requires_additional_review?(ShopOrderReview::REJECT)

      review = order.record_review(user: actor, verdict: ShopOrderReview::REJECT, reason: internal_reason)
      return failure(review.errors.full_messages.to_sentence) unless review.persisted?
      return nil unless order.requires_additional_review?(ShopOrderReview::REJECT)

      Result.new(
        order: order,
        rejected: false,
        review: review,
        message: "Rejection recorded (#{order.review_count(ShopOrderReview::REJECT)}/#{ShopOrderReview::REQUIRED_COUNT}). " \
                 "Order ##{order.id} now waits on another reviewer."
      )
    end

    def reject_accessories
      order.accessory_orders.select(&:may_mark_rejected?).count do |accessory|
        old_state = accessory.aasm_state
        accessory.internal_rejection_reason = internal_reason
        accessory.joe_case_url = joe_case_url
        accessory.fraud_related_project_id = fraud_project_id
        next false unless accessory.mark_rejected(reason) && accessory.save

        record_version(accessory, old_state, parent_order_cancelled: [ nil, order.id ])
        true
      end
    end

    def record_version(rejected_order, old_state, extra_changes = {})
      ::PaperTrail::Version.create!(
        item_type: "ShopOrder",
        item_id: rejected_order.id,
        event: "update",
        whodunnit: actor.id,
        object_changes: {
          aasm_state: [ old_state, rejected_order.aasm_state ],
          rejection_reason: [ nil, reason ],
          internal_rejection_reason: [ nil, internal_reason ],
          joe_case_url: [ nil, joe_case_url ],
          fraud_related_project_id: [ nil, fraud_project_id ]
        }.merge(extra_changes).compact_blank
      )
    end

    def success(message) = Result.new(order:, rejected: true, message:, review: nil)
    def failure(message) = Result.new(order:, rejected: false, message:, review: nil)
  end
end
