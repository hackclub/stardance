module Admin
  module FraudHelper
    # Which queue a review came from. The colour follows the source rather than
    # the verdict, so an item keeps the colour it was ranked under once it is
    # settled instead of changing meaning under the reviewer.
    def fraud_review_kind(record)
      case record
      when ::Project::Report then :flag
      when ::ShopOrder then :order
      when ::Certification::Integrity then :integrity
      end
    end

    # Whether the item has had its verdict, read off its own state so a slot
    # renders the same whether it came with the page or was swapped in.
    def fraud_review_resolved?(record)
      case record
      when ::Project::Report then !record.pending?
      when ::Certification::Integrity then !record.pending?
      when ::ShopOrder then !record.aasm_state.in?(::ShopOrder::FRAUD_REVIEW_STATES)
      else false
      end
    end
  end
end
