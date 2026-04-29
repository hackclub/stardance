class PostCreationToSlackJob < ApplicationJob
  queue_as :latency_5m

  discard_on ActiveJob::DeserializationError

  CHANNEL_ID = "C0A3WD1B24R"

  SLACK_MENTION_PATTERN = /<!(?:here|channel|everyone|subteam\^[A-Z0-9]+)(?:\|[^>]+)?>|@(?:here|channel|everyone)/i

  include Rails.application.routes.url_helpers

  def perform(record)
    return if Rails.env.development?

    case record
    when Post::Devlog
      post_devlog(record)
    when Project
      post_project(record)
    when Comment
      post_comment(record)
    end
  end

  private

  def post_devlog(devlog)
    post = devlog.post
    return unless post

    project = post.project
    author = post.user
    return unless project && author

    project.followers.each do |follower|
      if follower.send_notifications_for_followed_devlogs then
        SendSlackDmJob.perform_later(
          follower.slack_id,
          "New devlog on #{project.title} by #{author.display_name}!",
          blocks_path: "notifications/creations/followed_devlog_created",
          locals: {
            project_title: sanitize_mentions(project.title),
            project_url: project_url(project, host: "stardance.hackclub.com", protocol: "https"),
            author_name: sanitize_mentions(author.display_name) || "Someone",
            devlog_body: sanitize_mentions(devlog.body.to_s.truncate(200))
          }
        )
      end
    end

    SendSlackDmJob.perform_later(
      CHANNEL_ID,
      nil,
      blocks_path: "notifications/creations/devlog_created",
      locals: {
        project_title: sanitize_mentions(project.title),
        project_url: project_url(project, host: "stardance.hackclub.com", protocol: "https"),
        author_name: sanitize_mentions(author.display_name) || "Someone",
        devlog_body: sanitize_mentions(devlog.body.to_s.truncate(200))
      }
    )
  end

  def post_project(project)
    return if project.deleted?

    owner = project.memberships.owner.first&.user
    return unless owner

    SendSlackDmJob.perform_later(
      CHANNEL_ID,
      nil,
      blocks_path: "notifications/creations/project_created",
      locals: {
        project_title: sanitize_mentions(project.title),
        project_description: sanitize_mentions(project.description.to_s.truncate(200)),
        project_url: project_url(project, host: "stardance.hackclub.com", protocol: "https"),
        owner_name: sanitize_mentions(owner.display_name) || "Someone"
      }
    )
  end

  def post_comment(comment)
    commentable = comment.commentable
    author = comment.user
    return unless commentable && author

    commentable_url, commentable_title, commentable_users = resolve_commentable(commentable)
    return unless commentable_url
    commentable_users.each do |member|
      next if member.id == author.id
      if member.slack_id && member.send_notifications_for_new_comments
        SendSlackDmJob.perform_later(
          member.slack_id,
          "New comment on your project #{commentable_title} by #{author.display_name || "Someone"}",
          blocks_path: "notifications/creations/comment_created_dm",
          locals: {
            commentable_title: sanitize_mentions(commentable_title),
            commentable_url: commentable_url,
            author_name: sanitize_mentions(author.display_name) || "Someone",
            comment_body: sanitize_mentions(comment.body.to_s.truncate(200))
          }
        )
      end
    end
    SendSlackDmJob.perform_later(
      CHANNEL_ID,
      nil,
      blocks_path: "notifications/creations/comment_created",
      locals: {
        commentable_title: sanitize_mentions(commentable_title),
        commentable_url: commentable_url,
        author_name: sanitize_mentions(author.display_name) || "Someone",
        comment_body: sanitize_mentions(comment.body.to_s.truncate(200))
      }
    )
  end

  def resolve_commentable(commentable)
    case commentable
    when Post::Devlog
      post = commentable.post
      return nil unless post&.project

      [
        project_url(post.project, host: "stardance.hackclub.com", protocol: "https"),
        post.project.title,
        post.project.users
      ]
    when Post::ShipEvent
      post = commentable.post
      return nil unless post&.project

      [
        project_url(post.project, host: "stardance.hackclub.com", protocol: "https"),
        post.project.title,
        post.project.users
      ]
    else
      nil
    end
  end

  def sanitize_mentions(text)
    text.to_s.gsub(SLACK_MENTION_PATTERN, "")
  end
end
