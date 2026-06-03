# frozen_string_literal: true

module SemanticSearch
  class IndexRecordJob < ApplicationJob
    queue_as :default

    def perform(record_class_name, record_id)
      record_class = record_class_name.constantize
      record = record_class.find_by(id: record_id)

      if record
        SemanticSearch.upsert(record)
      else
        SemanticSearch.delete(type_for(record_class_name), record_id)
      end
    end

    private

    def type_for(record_class_name)
      {
        "Project" => "project",
        "Post::Devlog" => "devlog",
        "Post::ShipEvent" => "ship",
        "User" => "user"
      }[record_class_name]
    end
  end
end
