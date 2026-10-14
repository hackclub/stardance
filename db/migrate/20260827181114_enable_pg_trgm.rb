class EnablePgTrgm < ActiveRecord::Migration[8.1]
  # Trigram matching, so the admin queue search's unanchored ILIKE can ride a GIN
  # index instead of scanning the table. The indexes themselves land in
  # AddSearchIndexesForYswsQueue, which builds them concurrently — separate
  # migrations so a failed index build doesn't leave the extension half-applied.
  def change
    enable_extension "pg_trgm"
  end
end
