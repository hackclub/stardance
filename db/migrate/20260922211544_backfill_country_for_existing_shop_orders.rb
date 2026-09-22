class BackfillCountryForExistingShopOrders < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    ShopOrder.where(country: nil).find_each do |order|
      order.send(:set_country_from_address)
      order.update_column(:country, order.country) if order.country.present?
    end
  end

  def down
    # No-op: we don't want to remove countries on rollback
  end
end
