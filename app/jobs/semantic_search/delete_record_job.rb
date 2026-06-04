# frozen_string_literal: true

module SemanticSearch
  class DeleteRecordJob < ApplicationJob
    queue_as :default

    def perform(type, record_id)
      SemanticSearch.delete(type, record_id)
    end
  end
end
