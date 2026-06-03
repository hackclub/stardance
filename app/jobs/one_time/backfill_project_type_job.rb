# frozen_string_literal: true

class OneTime::BackfillProjectTypeJob < ApplicationJob
  queue_as :literally_whenever

  def scope
    Project.where(project_type: nil, deleted_at: nil).where.not(shipped_at: nil)
  end

  def perform
    count = 0

    scope.find_each do |project|
      Project::TypeCheckJob.perform_later(project)
      count += 1
    end

    Rails.logger.info "[OneTime::BackfillProjectType] Enqueued #{count} type-check jobs"
  end
end
