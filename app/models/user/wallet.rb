module User::Wallet
  extend ActiveSupport::Concern

  # Base Stardust price of the Outpost Ticket. The per-user discount
  # (outpost_discount_stardust) is subtracted from this; any overflow past it
  # becomes a flight stipend. Keep in sync with the ShopItem::OutpostTicket
  # record's ticket_cost.
  OUTPOST_TICKET_BASE = 300

  included do
    scope :top_by_balance, ->(limit = 10) { order(approx_balance: :desc).limit(limit) }
    scope :top_by_total_earned, ->(limit = 10) { order(approx_total_earned: :desc).limit(limit) }
  end

  class_methods do
    def balance_rank_for(user)
      where("approx_balance > ?", user.approx_balance).count + 1
    end

    def total_earned_rank_for(user)
      where("approx_total_earned > ?", user.approx_total_earned).count + 1
    end
  end

  def balance = ledger_entries.sum(:amount)

  def total_earned = ledger_entries.where("amount > 0").sum(:amount)

  # What this user would pay for the Outpost Ticket, floored at 0.
  def outpost_effective_price = [ 0, OUTPOST_TICKET_BASE - outpost_discount_stardust.to_i ].max

  # Discount accrued beyond what's needed to zero out the ticket — counts toward
  # a flight stipend.
  def outpost_flight_stipend = [ 0, outpost_discount_stardust.to_i - OUTPOST_TICKET_BASE ].max

  def cached_balance = Rails.cache.fetch(balance_cache_key) { balance }

  def balance_cache_key = "user/#{id}/sidebar_balance"

  def refresh_approx_balance!
    return unless self.class.column_names.include?("approx_balance")

    update_columns(
      approx_balance: balance,
      approx_total_earned: total_earned
    )
  end

  def invalidate_balance_cache!
    Rails.cache.delete(balance_cache_key)
    refresh_approx_balance!
  end

  def grant_email
    hcb_email.presence || email
  end
end
