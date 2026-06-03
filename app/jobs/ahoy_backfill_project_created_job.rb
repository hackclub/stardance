# frozen_string_literal: true

class AhoyBackfillProjectCreatedJob < ApplicationJob
  queue_as :default

  def perform
    result = ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO ahoy_events (name, user_id, time, properties)
      SELECT 'project_created', pm.user_id, MIN(pm.created_at), '{"source":"backfill"}'::jsonb
      FROM project_memberships pm
      WHERE NOT EXISTS (
        SELECT 1 FROM ahoy_events ae
        WHERE ae.user_id = pm.user_id AND ae.name = 'project_created'
      )
      GROUP BY pm.user_id
    SQL

    Rails.logger.info("[AhoyBackfillProjectCreated] backfilled #{result.cmd_tuples} events")
  end
end
