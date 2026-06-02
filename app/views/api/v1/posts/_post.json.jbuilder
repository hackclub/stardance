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
else
  ""
end
