class CreateShopItemSiteActionItems < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_item_site_action_items do |t|
      t.timestamps
    end
  end
end
