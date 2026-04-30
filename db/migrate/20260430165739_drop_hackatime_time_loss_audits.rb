class DropHackatimeTimeLossAudits < ActiveRecord::Migration[8.1]
  def up
    drop_table :hackatime_time_loss_audits, if_exists: true
  end

  def down
    create_table :hackatime_time_loss_audits do |t|
      t.datetime :audited_at, null: false
      t.datetime :created_at, null: false
      t.integer :devlog_total_seconds, default: 0, null: false
      t.integer :difference_seconds, default: 0, null: false
      t.text :hackatime_keys, default: "", null: false
      t.integer :per_project_sum_seconds, default: 0, null: false
      t.references :project, null: false, foreign_key: true
      t.integer :ungrouped_total_seconds, default: 0, null: false
      t.datetime :updated_at, null: false
      t.references :user, null: false, foreign_key: true

      t.index :audited_at
      t.index :difference_seconds
    end
  end
end
