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
      when ::ShopOrder then !record.aasm_state.in?(::ShopOrder::FRAUD_REVIEW_STATES) || fraud_review_passed_on?(record)
      else false
      end
    end

    # This reviewer gave their half of a two-review order, so it is finished
    # for them even though it stays open for someone else.
    def fraud_review_passed_on?(order)
      order.reviews.any? { |review| review.user_id == current_user.id } && order.awaiting_another_review?
    end

    # LedgerEntriesHelper links a reason at the reader's own pages, which on a
    # fraud review would send the reviewer to their own shop or achievements.
    # Only the project behind a payout is worth a link here, and it goes to the
    # admin view of it.
    def fraud_ledger_reason(entry)
      project = entry.ledgerable.is_a?(::Post::ShipEvent) ? entry.ledgerable.post&.project : nil
      return entry.reason unless project

      link_to entry.reason, admin_project_path(project), data: { turbo_frame: "_top" }
    end

    # The bulk form and every order's reject form offer the same projects, so
    # they are loaded once per render rather than once per order.
    def fraud_related_project_options(user)
      @fraud_related_project_options ||= {}
      @fraud_related_project_options[user.id] ||= user.projects.with_deleted.order(created_at: :desc)
                                                      .pluck(:title, :id, :deleted_at)
                                                      .map { |title, id, deleted_at| [ "#{title} (##{id}#{', deleted' if deleted_at})", id ] }
    end
  end
end
