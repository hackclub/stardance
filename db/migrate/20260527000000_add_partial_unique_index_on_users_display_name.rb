class AddPartialUniqueIndexOnUsersDisplayName < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = "index_users_on_lower_display_name_unique".freeze

  KERBAL_NAMES = %w[
    Jebediah Bill Bob Valentina Lodwig Shepard Gus Wernher Gene
    Mortimer Linus Genekin Bobnik Billard Valentik Aldler Orlas
    Neilbur Buzzig Mikevin Aldous Yurgus Laikus Grissom Shepnik
    Aldorf Scottbert Rodbur Danwig Franklis Aldwig Gordox
  ].freeze

  def up
    fill_blank_display_names
    sanitize_unsafe_characters
    resolve_duplicates

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

  private
    def generate_random_username
      "#{KERBAL_NAMES.sample}_Kerman_#{rand(1000..9999)}"
    end

    def fill_blank_display_names
      User.unscoped.where(display_name: [ nil, "" ]).find_each do |user|
        user.update_column(:display_name, generate_random_username)
      end
    end

    def sanitize_unsafe_characters
      User.unscoped.where.not(display_name: [ nil, "" ]).find_each do |user|
        sanitized = user.display_name.gsub(/[^a-zA-Z0-9_-]/, "_").first(30)
        user.update_column(:display_name, sanitized) if sanitized != user.display_name
      end
    end

    def resolve_duplicates
      dupes = User.unscoped
                  .where.not(display_name: [ nil, "" ])
                  .group("LOWER(display_name)")
                  .having("COUNT(*) > 1")
                  .pluck(Arel.sql("LOWER(display_name)"))

      dupes.each do |lowered_name|
        users = User.unscoped
                    .where("LOWER(display_name) = ?", lowered_name)
                    .order(:created_at)

        users.offset(1).find_each do |user|
          user.update_column(:display_name, generate_random_username)
        end
      end
    end
end
