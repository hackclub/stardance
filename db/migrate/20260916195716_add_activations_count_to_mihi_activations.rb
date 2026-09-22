class AddActivationsCountToMihiActivations < ActiveRecord::Migration[8.1]
  def change
    add_column :mihi_activations, :activations_count, :integer, default: 1, null: false
  end
end
