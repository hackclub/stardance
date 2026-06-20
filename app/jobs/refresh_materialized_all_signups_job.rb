# frozen_string_literal: true

class RefreshMaterializedAllSignupsJob < ApplicationJob
  queue_as :default

  # The refresh runs every 2 minutes (config/recurring.yml). If a refresh ever
  # takes longer than that, this keeps the next tick from piling a second
  # refresh on top of the running one.
  limits_concurrency to: 1, key: "refresh_materialized_all_signups", duration: 5.minutes

  def perform
    # CONCURRENTLY keeps the view readable (no AccessExclusive lock) while it
    # rebuilds. Requires the unique index on `email` created in the migration,
    # and that the view was already populated (it is created WITH DATA).
    ActiveRecord::Base.connection.execute(
      "REFRESH MATERIALIZED VIEW CONCURRENTLY materialized_all_signups"
    )
  end
end
