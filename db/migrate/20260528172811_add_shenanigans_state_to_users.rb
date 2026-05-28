class AddShenanigansStateToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :shenanigans_state, :jsonb, default: {}
  end
end
