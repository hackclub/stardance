class AddTelemetrySummaryToVoteAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :vote_assignments, :first_viewed_at, :datetime
    add_column :vote_assignments, :last_viewed_at, :datetime
    add_column :vote_assignments, :submitted_at, :datetime
    add_column :vote_assignments, :skipped_at, :datetime
    add_column :vote_assignments, :view_count, :integer, null: false, default: 0
  end
end
