class Api::V1::Users::Me::BalanceController < Api::BaseController
  include ApiAuthenticatable

  def index
    return unless (limit = api_limit)

    entries = current_api_user.ledger_entries.order(created_at: :desc)
    @pagy, @entries = pagy(entries, limit: limit)
    @balance = current_api_user.cached_balance
  end
end
