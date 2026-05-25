class CreateFaqItems < ActiveRecord::Migration[8.1]
  def change
    create_table :faq_items do |t|
      t.text :question, null: false
      t.text :answer, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :faq_items, :position
  end
end
