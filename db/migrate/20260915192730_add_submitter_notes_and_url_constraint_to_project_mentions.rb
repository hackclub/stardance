class AddSubmitterNotesAndUrlConstraintToProjectMentions < ActiveRecord::Migration[8.1]
  def change
    add_column :project_mentions, :submitter_notes, :text
    safety_assured { change_column_null :project_mentions, :url, false }
  end
end
