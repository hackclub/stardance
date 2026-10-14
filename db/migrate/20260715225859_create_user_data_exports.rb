class CreateUserDataExports < ActiveRecord::Migration[8.1]
  def change
    create_table :user_data_exports do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.string :zip_filename

      t.timestamps
    end

    add_index :user_data_exports, [ :user_id, :status ]
  end
end
