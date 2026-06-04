json.id post.id
json.type post.postable_type.demodulize.underscore
json.project_id post.project_id
json.user_id post.user_id
json.created_at post.created_at
json.updated_at post.updated_at

case post.postable_type
when "Post::Devlog"
  devlog = post.postable
  json.content do
    json.body devlog.body
    json.duration_seconds devlog.duration_seconds
    json.likes_count devlog.likes_count
    json.comments_count devlog.comments_count
    json.tutorial devlog.tutorial
    json.i_liked devlog.likes.exists?(user: @current_api_user)
    json.media devlog.attachments.map { |a|
      { url: rails_blob_path(a, only_path: true), content_type: a.content_type }
    }
  end
when "Post::ShipEvent"
  ship = post.postable
  json.content do
    json.certification_status ship.certification_status
    json.body ship.body
    json.feedback_reason ship.feedback_reason
    json.hours ship.hours
    json.payout ship.payout
  end
when "Post::Repost"
  repost = post.postable
  json.content do
    json.body repost.body
    json.original_post_id repost.original_post_id
    orig = repost.original_post
    if orig
      json.original_post do
        json.id orig.id
        json.type orig.postable_type.demodulize.underscore
        json.user_id orig.user_id
        json.created_at orig.created_at
        if orig.postable_type == "Post::Devlog" && orig.postable.present?
          json.content do
            json.body orig.postable.body
            json.likes_count orig.postable.likes_count
            json.comments_count orig.postable.comments_count
            json.duration_seconds orig.postable.duration_seconds
          end
        end
      end
    end
  end
else
  ""
end
