module User::Wallet
  extend ActiveSupport::Concern

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
