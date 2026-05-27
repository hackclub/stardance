class RenameFaqItemsToFaqs < ActiveRecord::Migration[8.1]
  def change
    drop_table :faqs
    safety_assured { rename_table :faq_items, :faqs }
  end
end
