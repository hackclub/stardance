class AddReviewTriageToProjectMentions < ActiveRecord::Migration[8.1]
  def change
    add_column :project_mentions, :internal_notes, :text
    add_column :project_mentions, :extra_links, :text
    add_column :project_mentions, :review_checklist, :string, array: true, default: [], null: false
    add_column :project_mentions, :on_hold_at, :datetime
    add_column :project_mentions, :proposed_action, :string
    add_column :project_mentions, :proposed_tier, :string
  end
end
