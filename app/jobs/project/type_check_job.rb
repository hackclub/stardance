# frozen_string_literal: true

class Project::TypeCheckJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(project)
    result = SwAi::ProjectTypeService.new(project).call
    project.update_column(:project_type, result.type) if result.ok && result.type.present?
  end
end
