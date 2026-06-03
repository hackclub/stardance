module User::Wallet
  extend ActiveSupport::Concern

  def balance = ledger_entries.sum(:amount)

  def total_earned = ledger_entries.where("amount > 0").sum(:amount)

  def cached_balance = Rails.cache.fetch(balance_cache_key) { balance }

  def cached_total_earned = Rails.cache.fetch(total_earned_cache_key) { total_earned }

  def balance_cache_key = "user/#{id}/sidebar_balance"

  def total_earned_cache_key = "user/#{id}/total_earned_balance"

  def invalidate_balance_cache!
    Rails.cache.delete(balance_cache_key)
    Rails.cache.delete(total_earned_cache_key)
  end

  def grant_email
    hcb_email.presence || email
  end
end
