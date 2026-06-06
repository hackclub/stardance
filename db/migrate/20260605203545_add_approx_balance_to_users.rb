class AddApproxBalanceToUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :users, :approx_balance, :integer, default: 0, null: false
    add_column :users, :approx_total_earned, :integer, default: 0, null: false

    add_index :users, :approx_balance, order: :desc, algorithm: :concurrently
    add_index :users, :approx_total_earned, order: :desc, algorithm: :concurrently

    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<~SQL
            UPDATE users SET
              approx_balance = COALESCE((SELECT SUM(amount) FROM ledger_entries WHERE ledger_entries.user_id = users.id), 0),
              approx_total_earned = COALESCE((SELECT SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) FROM ledger_entries WHERE ledger_entries.user_id = users.id), 0)
          SQL
        end
      end
    end
  end
end
