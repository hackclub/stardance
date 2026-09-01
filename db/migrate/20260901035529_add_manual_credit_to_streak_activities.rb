class AddManualCreditToStreakActivities < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :streak_activities, :manual_credit_at, :datetime, if_not_exists: true
    add_column :streak_activities, :manual_credit_reason, :string, if_not_exists: true
    add_reference :streak_activities, :manual_credit_by, index: { algorithm: :concurrently }, if_not_exists: true
    add_foreign_key :streak_activities, :users, column: :manual_credit_by_id, on_delete: :nullify, validate: false
    validate_foreign_key :streak_activities, :users, column: :manual_credit_by_id
  end
end
