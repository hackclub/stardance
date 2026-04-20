class DropShadowBanFromUsersAndProjects < ActiveRecord::Migration[8.1]
  def change
    remove_index :projects, :shadow_banned, if_exists: true
    safety_assured { remove_column :projects, :shadow_banned, :boolean, default: false, null: false }
    safety_assured { remove_column :projects, :shadow_banned_at, :datetime }
    safety_assured { remove_column :projects, :shadow_banned_reason, :text }

    safety_assured { remove_column :users, :shadow_banned, :boolean, default: false, null: false }
    safety_assured { remove_column :users, :shadow_banned_at, :datetime }
    safety_assured { remove_column :users, :shadow_banned_reason, :text }
  end
end
