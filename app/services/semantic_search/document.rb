# frozen_string_literal: true

module SemanticSearch
  class Document
    include Rails.application.routes.url_helpers

    attr_reader :record, :type, :record_id, :title, :subtitle, :preview, :path, :search_text, :updated_at

    def self.for(record)
      case record
      when Project
        return nil if record.deleted_at.present?

        new(
          record: record,
          type: "project",
          title: record.title,
          subtitle: "Project",
          preview: record.description,
          path: Rails.application.routes.url_helpers.project_path(record),
          search_text: [ record.title, record.description ].compact.join("\n")
        )
      when Post::Devlog
        return nil if record.deleted_at.present?

        post = record.post
        return nil unless post&.project

        new(
          record: record,
          type: "devlog",
          title: post.project.title,
          subtitle: "@#{post.user&.display_name || 'stardancer'} posted a devlog",
          preview: record.body,
          path: Rails.application.routes.url_helpers.project_devlog_path(post.project, record),
          search_text: [ "Devlog", post.project.title, post.user&.display_name, record.body ].compact.join("\n")
        )
      when Post::ShipEvent
        return nil if record.certification_status == "rejected"

        post = record.post
        return nil unless post&.project

        new(
          record: record,
          type: "ship",
          title: post.project.title,
          subtitle: "@#{post.user&.display_name || 'stardancer'} shipped",
          preview: record.body,
          path: Rails.application.routes.url_helpers.project_path(post.project, anchor: ActionView::RecordIdentifier.dom_id(post)),
          search_text: [ "Ship", post.project.title, post.user&.display_name, record.body ].compact.join("\n")
        )
      when User
        return nil if record.display_name.blank?

        new(
          record: record,
          type: "user",
          title: "@#{record.display_name}",
          subtitle: "Stardancer",
          preview: [ record.bio, interests_text(record) ].compact_blank.join(" "),
          path: Rails.application.routes.url_helpers.profile_path(record.display_name),
          search_text: [ record.display_name, record.bio, interests_text(record) ].compact_blank.join("\n")
        )
      end
    end

    def self.type_for(record)
      case record
      when Project then "project"
      when Post::Devlog then "devlog"
      when Post::ShipEvent then "ship"
      when User then "user"
      end
    end

    def self.redis_key_for(type, record_id)
      "#{SemanticSearch::DOC_PREFIX}#{type}:#{record_id}"
    end

    def self.interests_text(user)
      user.interests.to_a.map { |interest| User::INTEREST_LABELS[interest]&.to_s&.gsub(%r{</?wbr>}, "") || interest }.join(" ")
    end

    def initialize(record:, type:, title:, subtitle:, preview:, path:, search_text:)
      @record = record
      @type = type
      @record_id = record.id
      @title = title.to_s.squish
      @subtitle = subtitle.to_s.squish
      @preview = preview.to_s.squish.truncate(240)
      @path = path
      @search_text = search_text.to_s.squish
      @updated_at = record.updated_at || Time.current
    end

    def indexable?
      type.present? && record_id.present? && title.present? && path.present? && search_text.present?
    end

    def redis_key = self.class.redis_key_for(type, record_id)

    def record_key = "#{type}:#{record_id}"

    def to_redis_hash
      {
        "type" => type,
        "record_key" => record_key,
        "title" => title,
        "subtitle" => subtitle,
        "preview" => preview,
        "path" => path,
        "updated_at" => updated_at.to_i.to_s,
        "embedding_model" => SemanticSearch.model,
        "content_hash" => Digest::SHA256.hexdigest(search_text)
      }
    end

    def to_result
      result = {
        type: type,
        id: record_id,
        title: title,
        subtitle: subtitle,
        preview: preview,
        path: path
      }
      result[:avatar] = record.avatar if record.is_a?(User)
      result
    end
  end
end
