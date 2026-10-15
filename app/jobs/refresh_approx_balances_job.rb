class RefreshApproxBalancesJob < ApplicationJob
  queue_as :literally_whenever

  def perform
    earned = LedgerEntry.earnings.where("ledger_entries.user_id = users.id").select("SUM(ledger_entries.amount)")

    User.connection.execute(<<~SQL)
      UPDATE users SET
        approx_balance = COALESCE((SELECT SUM(amount) FROM ledger_entries WHERE ledger_entries.user_id = users.id), 0),
        approx_total_earned = COALESCE((#{earned.to_sql}), 0)
    SQL
  end
end
