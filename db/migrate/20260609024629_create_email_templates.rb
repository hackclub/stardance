class CreateEmailTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :email_templates do |t|
      t.string :name
      t.text :body

      t.timestamps
    end

    add_index :email_templates, :name, unique: true
  end
end
