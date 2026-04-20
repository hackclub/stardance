class DropScrapbookUrlFromPostDevlogs < ActiveRecord::Migration[8.1]
  def up
    safety_assured { remove_column :post_devlogs, :scrapbook_url, if_exists: true }

    begin
      User::Achievement.where(achievement_slug: "scrapbook_devlog").delete_all
    rescue StandardError => e
      Rails.logger.warn "Could not delete scrapbook_devlog user_achievements: #{e.message}"
    end

    begin
      if defined?(Flipper) && Flipper.exist?(:scrapbook_devlogs)
        Flipper.remove(:scrapbook_devlogs)
      end
    rescue StandardError => e
      Rails.logger.warn "Could not remove :scrapbook_devlogs flipper feature: #{e.message}"
    end
  end

  def down
    add_column :post_devlogs, :scrapbook_url, :string

    begin
      if defined?(Flipper) && !Flipper.exist?(:scrapbook_devlogs)
        Flipper.add(:scrapbook_devlogs)
      end
    rescue StandardError => e
      Rails.logger.warn "Could not re-add :scrapbook_devlogs flipper feature: #{e.message}"
    end
  end
end
