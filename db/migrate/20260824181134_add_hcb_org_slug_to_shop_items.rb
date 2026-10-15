class AddHCBOrgSlugToShopItems < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_items, :hcb_org_slug, :string
  end
end
