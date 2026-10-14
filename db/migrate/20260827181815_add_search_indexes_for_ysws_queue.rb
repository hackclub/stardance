class AddSearchIndexesForYswsQueue < ActiveRecord::Migration[8.1]
  # Backs the substring clauses in Certification::Ysws.search. projects.title had
  # no index at all, so every `title ILIKE '%q%'` in the admin was a sequential
  # scan; a trigram GIN index turns those into index scans.
  #
  # Nothing here for users.email or users.slack_id: the search matches those by
  # prefix and equality respectively, which the existing lower(email) and slack_id
  # btree indexes already serve.
  disable_ddl_transaction!

  INDEXES = {
    projects: %i[title repo_url demo_url],
    users: %i[display_name]
  }.freeze

  def up
    INDEXES.each do |table, columns|
      columns.each do |column|
        add_index table, column, using: :gin, opclass: :gin_trgm_ops,
                  name: trgm_index_name(table, column), algorithm: :concurrently
      end
    end
  end

  def down
    INDEXES.each do |table, columns|
      columns.each do |column|
        remove_index table, name: trgm_index_name(table, column), algorithm: :concurrently
      end
    end
  end

  private

  def trgm_index_name(table, column)
    "index_#{table}_on_#{column}_trgm"
  end
end
