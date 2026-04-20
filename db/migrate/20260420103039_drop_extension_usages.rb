class DropExtensionUsages < ActiveRecord::Migration[8.1]
  def change
    drop_table :extension_usages
  end
end
