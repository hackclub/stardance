# frozen_string_literal: true

module TimelinePostPreloading
  extend ActiveSupport::Concern

  private

  def preload_timeline_postables(posts, project_context: false)
    grouped = posts.group_by(&:postable_type)

    preload_timeline_group(posts, :user)
    preload_timeline_group(posts_requiring_timeline_project(grouped, project_context: project_context), :project)
    preload_timeline_group(grouped["Post::Devlog"], postable: { attachments_attachments: :blob })
    preload_timeline_group(
      grouped["Post::ShipEvent"],
      postable: [ { attachments_attachments: :blob }, { mission_submission: :mission } ]
    )
  end

  # The original post ids among `posts` that the current user has reposted, so
  # Posts::CardComponent can show repost state without a query per card.
  def reposted_post_ids_for(posts)
    return Set.new unless current_user

    repost_target_ids = posts.filter_map do |post|
      if post.postable_type == "Post::Devlog"
        post.id
      elsif post.repost?
        post.postable&.original_post_id
      end
    end
    return Set.new if repost_target_ids.empty?

    Post::Repost
      .where(user: current_user, original_post_id: repost_target_ids)
      .pluck(:original_post_id)
      .to_set
  end

  # The devlog ids among `posts` (and the devlogs they repost) that the current
  # user has liked, so likes/_button can show like state without a query per card.
  def liked_devlog_ids_for(posts)
    return Set.new unless current_user

    devlog_ids = posts.filter_map do |post|
      if post.postable_type == "Post::Devlog"
        post.postable_id
      elsif post.repost?
        original = post.postable&.original_post
        original.postable_id if original&.postable_type == "Post::Devlog"
      end
    end
    return Set.new if devlog_ids.empty?

    Like.where(user: current_user, likeable_type: "Post::Devlog", likeable_id: devlog_ids).pluck(:likeable_id).to_set
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
