# Finality: the ship-early event for the last week. A ship posted on one of
# the bonus days (New York time) earns that share of its stardust payout on
# top, as its own ledger entry, and puts its shipper in the raffle pool.
#
# The bonus is issued alongside the payout itself (see
# Post::ShipEvent::Payouts#issue_payout) while the :finality_bonus flag is on.
# award_missing! catches up any ship that was paid while the flag was off.
module Finality
  TIME_ZONE = "America/New_York".freeze
  FEATURE_FLAG = :finality_bonus
  RAFFLE_FEATURE_FLAG = :finality_raffle
  BONUS_CREATED_BY = "finality_bonus".freeze
  BONUS_RATES = {
    Date.new(2026, 10, 27) => 0.08,
    Date.new(2026, 10, 28) => 0.06,
    Date.new(2026, 10, 29) => 0.04,
    Date.new(2026, 10, 30) => 0.02,
    Date.new(2026, 10, 31) => 0.01
  }.freeze
  # Ships that can never pay: rejected outright, or bounced to the wrong queue.
  INELIGIBLE_STATUSES = Post::ShipEvent::HIDDEN_STATUSES
  RAFFLE_PRIZES = [
    { key: "xbox", name: "Xbox Series S", detail: "for when you're done coding", quantity: 5, image: "finality/xbox.webp" },
    { key: "artemis", name: "LEGO Artemis set", detail: "a rocket. made of LEGO.", quantity: 5, image: "finality/artemis.webp" },
    { key: "vip", name: "Kennedy Space Center", detail: "VIP ticket + flights*", quantity: 2, image: "finality/kennedy-vip.webp" },
    { key: "kennedy", name: "Kennedy Space Center", detail: "Visitor ticket", quantity: 50, image: "finality/kennedy.webp" }
  ].map(&:freeze).freeze

  class << self
    def enabled? = Flipper.enabled?(FEATURE_FLAG)

    def raffle_enabled? = Flipper.enabled?(RAFFLE_FEATURE_FLAG)

    # The bonus a ship posted right now would earn, or nil outside the window
    # or while the bonus is switched off.
    def current_rate(at = Time.current)
      BONUS_RATES[at.in_time_zone(TIME_ZONE).to_date] if enabled?
    end

    def raffle_prize(key)
      RAFFLE_PRIZES.find { |prize| prize[:key] == key }
    end

    def raffle_candidates
      ships.unscope(:includes, :order).joins(post: :user).where(users: { banned: false })
    end

    def approved_raffle_ships
      raffle_candidates.where(certification_status: "approved")
    end

    def pending_raffle_ships
      raffle_candidates.where.not(certification_status: [ "approved", *INELIGIBLE_STATUSES ])
                       .or(raffle_candidates.where(certification_status: nil))
    end

    def window
      BONUS_RATES.keys.min.in_time_zone(TIME_ZONE)...(BONUS_RATES.keys.max + 1).in_time_zone(TIME_ZONE)
    end

    # Every ship posted inside the window, oldest first.
    def ships
      Post::ShipEvent.joins(:post)
                     .where(posts: { created_at: window })
                     .includes(:ledger_entries, :project, post: :user)
                     .order("posts.created_at ASC, post_ship_events.id ASC")
    end

    def ship_day(ship_event) = ship_event.post&.created_at&.in_time_zone(TIME_ZONE)&.to_date

    def rate_for(ship_event) = BONUS_RATES[ship_day(ship_event)]

    # Nil until the ship has been paid; banned shippers earn nothing.
    def bonus_for(ship_event)
      rate = rate_for(ship_event)
      return nil if rate.nil? || ship_event.payout.blank? || ship_event.payout_recipient&.banned?

      (ship_event.payout * rate).round
    end

    def bonus_entry(ship_event)
      ship_event.ledger_entries.find { |entry| entry.created_by == BONUS_CREATED_BY }
    end

    # Idempotent: rechecked under the ship's row lock, so a payout that's
    # retried, or a catch-up run racing it, never pays the bonus twice.
    def award_bonus!(ship_event)
      return false unless enabled?

      amount = bonus_for(ship_event)
      return false unless amount&.positive?

      ship_event.with_lock do
        return false if ship_event.ledger_entries.exists?(created_by: BONUS_CREATED_BY)

        ship_event.ledger_entries.create!(
          user: ship_event.payout_recipient,
          amount: amount,
          reason: "Finality bonus (#{(rate_for(ship_event) * 100).round}%): #{ship_event.project&.title || 'Unknown project'}",
          created_by: BONUS_CREATED_BY
        )
      end
      true
    end

    def award_missing!
      # award_bonus! rechecks the ledger under the row lock, so no preload.
      ships.unscope(:includes).includes(:project, post: :user)
           .where.not(payout: nil).to_a.count { |ship_event| award_bonus!(ship_event) }
    end

    # Each approved ship is a separate entry. Later rejections remove that
    # entry automatically; approval can happen after the submission window.
    def raffle_entry_ids(ship_events = ships.to_a)
      ship_events.select { |ship_event| ship_event.certification_status == "approved" && !raffle_ineligible?(ship_event) }
                 .to_set(&:id)
    end

    # A small aggregate query for the public page, without loading the whole pool.
    def raffle_counts_for(user)
      return { confirmed: 0, pending: 0 } unless user && !user.banned?

      counts = ships.unscope(:includes, :order)
                    .where(posts: { user_id: user.id })
                    .group(:certification_status).count
                    .except(*INELIGIBLE_STATUSES)
      confirmed = counts.fetch("approved", 0)
      { confirmed: confirmed, pending: counts.values.sum - confirmed }
    end

    def raffle_ineligible?(ship_event)
      ship_event.payout_recipient.nil? ||
        ship_event.payout_recipient.banned? ||
        !window.cover?(ship_event.post.created_at) ||
        ship_event.certification_status.in?(INELIGIBLE_STATUSES)
    end
  end
end
