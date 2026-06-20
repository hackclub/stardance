# frozen_string_literal: true

module TimelinePostPreloading
  extend ActiveSupport::Concern

  private

  def preload_timeline_postables(posts, project_context: false)
    grouped = posts.group_by(&:postable_type)

    preload_timeline_group(posts, :user)
    preload_timeline_group(posts_requiring_timeline_project(grouped, project_context: project_context), :project)
    preload_timeline_group(grouped["Post::Devlog"], postable: :attachments_attachments)
    preload_timeline_group(
      grouped["Post::ShipEvent"],
      postable: [ :attachments_attachments, { mission_submission: :mission } ]
    )
  end

  def preload_timeline_group(records, associations)
    return if records.blank?

    ActiveRecord::Associations::Preloader
      .new(records: records, associations: associations)
      .call
  end

  def posts_requiring_timeline_project(grouped, project_context:)
    if project_context
      grouped.except("Post::ShipEvent").values.flatten
    else
      grouped.values.flatten
    end
  end
end
