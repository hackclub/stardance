class CreateCertificates < ActiveRecord::Migration[8.1]
  def change
    create_table :certificates do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :code, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "pending"
      t.float :hours_at_issue, null: false

      t.timestamps
    end
    add_index :certificates, :code, unique: true
  end
end
