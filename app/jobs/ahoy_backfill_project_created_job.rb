# frozen_string_literal: true

class AhoyBackfillProjectCreatedJob < ApplicationJob
  queue_as :default

  def perform
    already_tracked = Ahoy::Event
      .where(name: "project_created")
      .where.not(user_id: nil)
      .distinct
      .pluck(:user_id)

    missing = Project::Membership
      .where.not(user_id: already_tracked)
      .group(:user_id)
      .minimum(:created_at)

    return if missing.empty?

    rows = missing.map do |user_id, first_project_at|
      { name: "project_created", user_id: user_id, time: first_project_at, properties: { source: "backfill" } }
    end

    Ahoy::Event.insert_all(rows)

    Rails.logger.info("[AhoyBackfillProjectCreated] backfilled #{rows.size} events")
  end
end
