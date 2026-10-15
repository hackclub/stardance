class AddRerollValueToDailyRolls < ActiveRecord::Migration[8.1]
  def change
    add_column :daily_rolls, :reroll_value, :integer
  end
end
