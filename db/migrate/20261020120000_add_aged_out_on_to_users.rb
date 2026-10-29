class AddAgedOutOnToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :aged_out_on, :date
  end
end
