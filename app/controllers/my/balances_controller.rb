class My::BalancesController < ApplicationController
  def show
    authorize :my, :show_balance?

    @body_class = "app-layout-page"

    @pagy, @balance = pagy(
      current_user.ledger_entries.includes(:ledgerable).order(created_at: :desc),
      limit: 50
    )
  end
end
