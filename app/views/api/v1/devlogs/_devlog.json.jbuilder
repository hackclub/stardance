json.extract! devlog, :id, :body, :duration_seconds, :likes_count, :comments_count,
              :tutorial, :created_at, :updated_at

json.project_id devlog.post&.project_id
json.media devlog.attachments.map { |attachment|
  {
    url: rails_blob_path(attachment, only_path: true),
    content_type: attachment.content_type
  }
}
