# frozen_string_literal: true

module SemanticSearchIndexable
  extend ActiveSupport::Concern

  class_methods do
    def semantic_search_indexable(type:)
      after_commit :enqueue_semantic_search_index, on: %i[create update]
      after_commit -> { enqueue_semantic_search_delete(type) }, on: :destroy
    end
  end

  private

  def enqueue_semantic_search_index
    SemanticSearch::IndexRecordJob.perform_later(self.class.name, id)
  end

  def enqueue_semantic_search_delete(type)
    SemanticSearch::DeleteRecordJob.perform_later(type, id)
  end
end
