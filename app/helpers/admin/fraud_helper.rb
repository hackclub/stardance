module Admin
  module FraudHelper
    # The tone a settled review paints into the progress bar, or nil while the
    # item is still waiting on a verdict. Read off the item's own state so a
    # slot renders the same whether it came with the page or was swapped in by
    # a verdict, with no verdict history to keep in sync.
    def fraud_verdict_tone(record)
      case record
      when ::Project::Report then fraud_report_tone(record)
      when ::Certification::Integrity then fraud_integrity_tone(record)
      when ::ShopOrder then fraud_order_tone(record)
      end
    end

    # Which queue a review came from, so a slot can be ghosted in that source's
    # colour while it is still waiting on a verdict.
    def fraud_review_kind(record)
      case record
      when ::Project::Report then :flag
      when ::ShopOrder then :order
      when ::Certification::Integrity then :integrity
      end
    end

    private

    def fraud_report_tone(report)
      return if report.pending?

      report.dismissed? ? :cleared : :struck
    end

    def fraud_integrity_tone(check)
      case check.status
      when "auto_passed", "manually_passed" then :cleared
      when "deducted" then :reduced
      when "banned" then :struck
      end
    end

    def fraud_order_tone(order)
      return if order.aasm_state.in?(::ShopOrder::FRAUD_REVIEW_STATES)

      order.rejected? ? :struck : :cleared
    end
  end
end
