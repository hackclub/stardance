class AddOneActiveMissionIndexToProjectMissionAttachments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Detach all but the newest active attachment per project so the unique
    # index can build. Tiny table; mirrors the app-level v1 policy.
    safety_assured do
      execute <<~SQL
        UPDATE project_mission_attachments
        SET detached_at = NOW()
        WHERE detached_at IS NULL AND deleted_at IS NULL
          AND id NOT IN (
            SELECT DISTINCT ON (project_id) id
            FROM project_mission_attachments
            WHERE detached_at IS NULL AND deleted_at IS NULL
            ORDER BY project_id, attached_at DESC, id DESC
          )
      SQL
    end

    add_index :project_mission_attachments, :project_id,
              unique: true,
              where: "detached_at IS NULL AND deleted_at IS NULL",
              name: "index_project_mission_attachments_one_active",
              algorithm: :concurrently
  end

  def down
    remove_index :project_mission_attachments,
                 name: "index_project_mission_attachments_one_active",
                 algorithm: :concurrently
  end
end
