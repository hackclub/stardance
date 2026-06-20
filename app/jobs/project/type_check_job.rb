# frozen_string_literal: true

class Project::TypeCheckJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(project)
    result = SwAi::ProjectTypeService.new(project).call
    return unless result.ok && result.type.present?

    project.update_column(:project_type, result.type)
    sync_type_to_gorse_later(project)
  end

  private

  def sync_type_to_gorse_later(project)
    project.sync_to_gorse_later
    project.posts.of_ship_events.find_each(&:sync_to_gorse_later)
  end
end
