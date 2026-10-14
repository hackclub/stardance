class CreateMissionPrizeRedemptions < ActiveRecord::Migration[8.1]
  def change
    create_table :mission_prize_redemptions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :mission, null: false, foreign_key: true
      t.references :mission_prize, null: false, foreign_key: true
      t.references :shop_order, null: false, foreign_key: true, index: { unique: true }
      t.references :source, polymorphic: true, null: false

      t.timestamps
    end

    add_index :mission_prize_redemptions,
              [ :source_type, :source_id, :mission_prize_id ],
              unique: true,
              name: "index_prize_redemptions_on_source_and_prize"
  end
end
