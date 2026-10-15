class CreateWorkshopAttendances < ActiveRecord::Migration[8.1]
  def change
    create_table :workshop_attendances do |t|
      t.references :workshop, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true

      t.timestamps

      t.index [ :workshop_id, :user_id ], unique: true
    end
  end
end
