json.extract! devlog, :id, :body, :duration_seconds, :likes_count, :comments_count,
                      :created_at, :updated_at

json.media devlog.attachments do |attachment|
  json.url rails_blob_url(attachment)
  json.content_type attachment.content_type
end

json.comments devlog.thread_comments do |comment|
  json.extract! comment, :id, :body, :created_at, :updated_at

  json.author do
    json.extract! comment.user, :id, :display_name
    json.avatar comment.user.avatar
  end
end
