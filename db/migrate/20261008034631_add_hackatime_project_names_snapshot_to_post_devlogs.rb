class AddHackatimeProjectNamesSnapshotToPostDevlogs < ActiveRecord::Migration[8.1]
  def change
    add_column :post_devlogs, :hackatime_project_names_snapshot, :text, array: true
  end
end
