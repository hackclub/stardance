class AddCategoryToMissionPrizes < ActiveRecord::Migration[8.1]
  def change
    add_column :mission_prizes, :category, :integer, null: false, default: 0
  end
end
