# frozen_string_literal: true

class Gorse::ProjectPayload
  PLACEHOLDER_TITLES = %w[mystring untitled].freeze

  def initialize(project)
    @project = project
  end

  def self.recommendable_scope(viewer)
    Project.excluding_member(viewer)
           .where(deleted_at: nil)
           .where.not(title: [ nil, "" ])
           .where.not(description: [ nil, "" ])
           .where("LOWER(projects.title) NOT IN (?)", PLACEHOLDER_TITLES)
           .where("LOWER(projects.title) NOT LIKE ?", "untitled%")
           .where("projects.devlogs_count > 0 OR projects.shipped_at IS NOT NULL OR projects.duration_seconds > 0")
           .joins("INNER JOIN active_storage_attachments asa ON asa.record_id = projects.id AND asa.record_type = 'Project' AND asa.name = 'banner'")
  end

  def to_h
    {
      ItemId: Gorse::Ids.project(project),
      Categories: categories,
      Labels: labels,
      Timestamp: timestamp.iso8601,
      IsHidden: hidden?,
      Comment: project.title.to_s
    }
  end

  def hidden?
    project.deleted_at.present? || low_information? || rejected_latest_ship?
  end

  private
    attr_reader :project

    def categories
      [ "project", project.project_type, project.project_categories ].flatten.compact_blank.uniq
    end

    def labels
      Gorse::Labels.cast(
        project_categories: project.project_categories,
        project_type: project.project_type,
        ship_status: project.ship_status,
        tutorial: project.tutorial?,
        has_banner: project.banner.attached?,
        has_demo: project.demo_url.present?,
        has_repo: project.repo_url.present?,
        fire: project.marked_fire_at.present?
      )
    end

    def timestamp
      project.shipped_at || project.created_at || Time.current
    end

    def low_information?
      project.title.blank? ||
        project.description.blank? ||
        PLACEHOLDER_TITLES.include?(project.title.to_s.parameterize) ||
        (project.devlogs_count.to_i.zero? && project.shipped_at.blank? && project.duration_seconds.to_i.zero?)
    end

    def rejected_latest_ship?
      project.ship_events.order(created_at: :desc).first&.certification_status == "rejected"
    end
end
