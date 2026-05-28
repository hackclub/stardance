class AddPartialUniqueIndexOnUsersDisplayName < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = "index_users_on_lower_display_name_unique".freeze

  def up
    dupes = User.unscoped
                .where.not(display_name: [ nil, "" ])
                .group("LOWER(display_name)")
                .having("COUNT(*) > 1")
                .count
    if dupes.any?
      raise "Refusing to add unique index: #{dupes.size} duplicate display_name group(s) found. " \
            "Sample: #{dupes.first(5).map { |k, v| "#{k}=#{v}" }.join(', ')}"
    end

    return if index_exists?(:users, "LOWER(display_name)", name: INDEX_NAME)

    add_index :users, "LOWER(display_name)", unique: true,
              where: "display_name IS NOT NULL AND display_name <> ''",
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  def down
    return unless index_exists?(:users, "LOWER(display_name)", name: INDEX_NAME)

    remove_index :users, name: INDEX_NAME, algorithm: :concurrently
  end
end
