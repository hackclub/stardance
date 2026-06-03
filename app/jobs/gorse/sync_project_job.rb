# frozen_string_literal: true

class Gorse::SyncProjectJob < ApplicationJob
  queue_as :default

  def perform(project)
    project.sync_to_gorse_now
  end
end
