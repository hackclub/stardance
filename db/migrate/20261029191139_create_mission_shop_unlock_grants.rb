class CreateMissionShopUnlockGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :mission_shop_unlock_grants do |t|
      t.references :mission, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :granted_by, null: false, foreign_key: { to_table: :users }
      t.string :reason

      t.timestamps
    end
    add_index :mission_shop_unlock_grants, [ :mission_id, :user_id ], unique: true
  end
end
