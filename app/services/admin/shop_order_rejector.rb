module Admin
  class ShopOrderRejector
    Result = Data.define(:order, :rejected, :message) do
      def rejected? = rejected
    end

    def initialize(order, actor:, reason: nil, internal_reason: nil, joe_case_url: nil, fraud_project_id: nil)
      @order = order
      @actor = actor
      @reason = reason.presence || "No reason provided"
      fraud_reviewer = actor.admin? || actor.fraud_dept?
      @internal_reason = fraud_reviewer ? internal_reason.presence : @reason
      @joe_case_url = fraud_reviewer ? joe_case_url.presence : nil
      @fraud_project_id = fraud_reviewer ? fraud_project_id.presence : 1
    end

    def call
      return failure("This is a high-value order and requires 2 fraud dept reviews before rejection (#{order.reviews.count}/2 so far).") if order.requires_additional_review?

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

    def success(message) = Result.new(order:, rejected: true, message:)
    def failure(message) = Result.new(order:, rejected: false, message:)
  end
end
