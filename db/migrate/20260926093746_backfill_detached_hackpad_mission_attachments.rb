class BackfillDetachedHackpadMissionAttachments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    unless Mission.exists?(slug: "hackpad")
      say "Skipping detached Hackpad repairs: no Hackpad mission exists."
      return
    end

    previous_lock_timeout = connection.select_value("SHOW lock_timeout")
    begin
      connection.execute("SET lock_timeout = '10s'")
      say_with_time "Restoring detached Hackpad mission attachments" do
        # Keep this audited, idempotent job and its historical-attachment
        # restore behavior available while this migration is replayable.
        OneTime::BackfillDetachedHackpadsJob.perform_now(dry_run: false)
      end
    ensure
      connection.execute("SET lock_timeout = #{connection.quote(previous_lock_timeout)}")
    end
  end

  def down
    # Repairs and their audit history must survive rollback.
  end
end
