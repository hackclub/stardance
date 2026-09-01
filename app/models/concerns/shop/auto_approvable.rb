module Shop
  # Clears a shop order through fraud review without a human: either the buyer's
  # shipping history is already vouched for and the order is cheap enough that a
  # mistake is affordable, or the order is a Sticky Streak sticker, which the
  # streak itself has already earned.
  module AutoApprovable
    extend ActiveSupport::Concern

    # Ceiling on what Hack Club actually pays out (usd_cost), not the stardust
    # price. Orders at or above it always go to a person.
    MAX_AUTO_APPROVE_USD = 100

    # Integrity verdicts that count as cleared. A deduction already took its
    # hours off the payout, so it is not a reason to hold the goods. `pending`
    # is not a pass, and a ship carrying no check at all has never been looked
    # at, so neither one clears.
    CLEARED_INTEGRITY_STATUSES = %w[auto_passed manually_passed deducted].freeze

    WHODUNNIT = "Shop::AutoApprovable".freeze

    # Raised when an unattended fulfilment blew up, so the job can back off and
    # try again rather than abandoning the order on a transient HCB fault.
    FulfilmentFailed = Class.new(StandardError)

    # One ship in a buyer's history, paired with the integrity verdict on it.
    # A nil status means no check was ever written, which never clears.
    Ship = Struct.new(:id, :shipped_at, :integrity_status)

    included do
      after_commit :enqueue_auto_approval, if: :entered_fraud_review?
    end

    class_methods do
      # Answers auto-approvability for a batch of orders in a fixed number of
      # queries, so a queue can sort by it without asking once per row.
      def auto_approvable_ids(orders)
        orders = orders.to_a
        return [] if orders.empty?

        histories = ship_histories_for(orders.map(&:user_id).uniq)
        orders.select { |order| order.auto_approvable?(ships: histories[order.user_id] || []) }
              .map(&:id)
      end

      # Every ship these buyers have posted, with its integrity verdict, keyed
      # by user. Two queries regardless of how many buyers are asked about.
      def ship_histories_for(user_ids)
        posts = Post.where(postable_type: "Post::ShipEvent", user_id: user_ids)
                    .pluck(:user_id, :postable_id, :created_at)

        # pluck casts an enum back to its label, but normalise anyway so a raw
        # integer would compare the same.
        verdicts = ::Certification::Integrity
                     .where(ship_event_id: posts.map { |(_, ship_id, _)| ship_id })
                     .pluck(:ship_event_id, :status)
                     .to_h { |ship_id, status| [ ship_id, ::Certification::Integrity.statuses.key(status) || status&.to_s ] }

        posts.group_by(&:first).transform_values do |rows|
          rows.map { |(_, ship_id, shipped_at)| Ship.new(ship_id, shipped_at, verdicts[ship_id]) }
        end
      end
    end

    # A Sticky Streak sticker is earned by keeping the streak and costs a stamp,
    # so there is nothing for a reviewer to decide. These clear on their own
    # whatever the buyer's ship history says.
    def sticky_streak_sticker?
      shop_item.is_a?(ShopItem::StickyStreakSticker)
    end

    # `ships` lets a caller hand over a buyer's already-loaded ship history;
    # left out, the order fetches its own.
    def auto_approvable?(ships: nil)
      return false unless pending?
      return true if sticky_streak_sticker?
      return false unless Flipper.enabled?(:shop_auto_approve)
      # Accessories are approved alongside whatever they ride on, and their
      # value is already counted against the parent's ceiling.
      return false if parent_order_id.present?
      return false unless user.eligible_for_shop?
      return false if shop_item.requires_verification_call?
      # Keeps the two-reviewer rule on expensive orders out of reach.
      return false if high_value?

      total = auto_approval_usd_total
      return false if total.nil? || total >= MAX_AUTO_APPROVE_USD

      prior_ships_cleared?(ships)
    end

    def auto_approve!
      return false unless auto_approvable?

      approved = PaperTrail.request(whodunnit: WHODUNNIT) do
        if shop_item.respond_to?(:fulfill!)
          fulfil_unattended
        else
          queue_for_fulfillment && save
        end
      end

      record_auto_approval if approved
      approved
    end

    # Real-dollar exposure of everything shipping under this order: the item,
    # its modifiers, and the accessories riding along. A missing cost anywhere
    # returns nil, because an unknown price is not the same as a cheap one.
    def auto_approval_usd_total
      item_usd = shop_item.usd_cost
      return nil if item_usd.blank?

      accessories = accessory_orders.includes(:shop_item).to_a
      return nil if accessories.any? { |accessory| accessory.shop_item.usd_cost.blank? }

      modifiers_usd = selected_modifiers.sum { |modifier| modifier.usd_cost || 0 }
      accessories_usd = accessories.sum { |accessory| accessory.shop_item.usd_cost * accessory.quantity }

      (item_usd * quantity) + modifiers_usd + accessories_usd
    end

    # Leaves the failure where a reviewer can see it. Without this an order that
    # the system tried and failed to approve looks untouched in the admin UI.
    def record_auto_approval_failure(error)
      ::PaperTrail::Version.create!(
        item_type: "ShopOrder",
        item_id: id,
        event: "auto_approval_failed",
        whodunnit: WHODUNNIT,
        object_changes: {
          error: error.message.truncate(500),
          usd_total: auto_approval_usd_total.to_s
        }
      )
    end

    private

    # Self-fulfilling items settle the moment they are approved, and for HCB
    # grants that disburses real money. Failures are re-raised so the job can
    # retry them: Shop::HCBGrantFulfillable records the disbursement against
    # the order before marking it fulfilled, so a second attempt finishes the
    # bookkeeping instead of paying twice.
    def fulfil_unattended
      approve!
      reload.fulfilled?
    rescue StandardError => e
      raise FulfilmentFailed, "shop order #{id}: #{e.message}"
    end

    # Fires when the order lands in the fraud queue: on creation, and when
    # Shop::ProcessVerifiedOrdersJob releases it after identity verification.
    # Coming off a hold is excluded, since someone parked it deliberately.
    def entered_fraud_review?
      return false unless pending?
      return false unless previously_new_record? || saved_change_to_aasm_state?

      aasm_state_before_last_save != "on_hold"
    end

    # Out of band rather than inline: approving saves the record again, and a
    # nested save inside a commit callback reorders the remaining callbacks on
    # this same commit (the buyer's status notification among them).
    def enqueue_auto_approval
      Shop::AutoApproveJob.perform_later(self)
    end

    # Every ship posted before the order needs an integrity verdict, and none of
    # them may be a fraud verdict.
    def prior_ships_cleared?(ships = nil)
      prior = prior_ships(ships)
      return false if prior.empty?

      prior.all? { |ship| CLEARED_INTEGRITY_STATUSES.include?(ship.integrity_status) }
    end

    def prior_ships(ships = nil)
      @prior_ships ||= begin
        history = ships || self.class.ship_histories_for([ user_id ])[user_id] || []
        history.select { |ship| ship.shipped_at <= created_at }
      end
    end

    def prior_ship_event_ids
      prior_ships.map(&:id)
    end

    # PaperTrail already records the state transition under WHODUNNIT; this
    # carries the evidence the decision rested on, so an auditor can reconstruct
    # it without re-deriving the buyer's ship history.
    def record_auto_approval
      ::PaperTrail::Version.create!(
        item_type: "ShopOrder",
        item_id: id,
        event: "auto_approved",
        whodunnit: WHODUNNIT,
        object_changes: auto_approval_evidence.merge(result_state: aasm_state)
      )
    end

    # What the verdict rested on. A streak sticker was cleared by its item type,
    # so recording a ship history it never consulted would misreport the reason.
    def auto_approval_evidence
      if sticky_streak_sticker?
        { reason: "sticky_streak_sticker", shop_item_id: shop_item_id }
      else
        {
          usd_total: auto_approval_usd_total.to_s,
          usd_ceiling: MAX_AUTO_APPROVE_USD,
          cleared_ship_event_ids: prior_ship_event_ids
        }
      end
    end
  end
end
