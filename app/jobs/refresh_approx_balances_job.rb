class RefreshApproxBalancesJob < ApplicationJob
  queue_as :default

  def perform
    User.connection.execute(<<~SQL)
      UPDATE users SET
        approx_balance = COALESCE((SELECT SUM(amount) FROM ledger_entries WHERE ledger_entries.user_id = users.id), 0),
        approx_total_earned = COALESCE((SELECT SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) FROM ledger_entries WHERE ledger_entries.user_id = users.id), 0)
    SQL
  end
end
