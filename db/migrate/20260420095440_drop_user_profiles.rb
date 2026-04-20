class DropUserProfiles < ActiveRecord::Migration[8.1]
  def up
    safety_assured { drop_table :user_profiles, if_exists: true }

    begin
      if defined?(Flipper) && Flipper.exist?(:user_profiles)
        Flipper.remove(:user_profiles)
      end
    rescue StandardError => e
      Rails.logger.warn "Could not remove :user_profiles flipper feature: #{e.message}"
    end
  end

  def down
    create_table :user_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.text :bio
      t.text :custom_css

      t.timestamps
    end
  end
end
