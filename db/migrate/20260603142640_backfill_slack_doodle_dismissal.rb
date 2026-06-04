class BackfillSlackDoodleDismissal < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute <<~SQL
        UPDATE users
        SET things_dismissed = array_append(things_dismissed, 'slack_doodle')
        WHERE id IN (SELECT user_id FROM user_identities WHERE provider = 'hack_club')
          AND NOT ('slack_doodle' = ANY(things_dismissed))
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL
        UPDATE users
        SET things_dismissed = array_remove(things_dismissed, 'slack_doodle')
      SQL
    end
  end
end
