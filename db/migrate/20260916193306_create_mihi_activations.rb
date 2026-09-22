class CreateMihiActivations < ActiveRecord::Migration[8.1]
  def change
    create_table :mihi_activations do |t|
      t.references :user, null: false, foreign_key: true
      t.date :activated_on, null: false

      t.timestamps
    end
    add_index :mihi_activations, [ :activated_on, :user_id ], unique: true
  end
end
