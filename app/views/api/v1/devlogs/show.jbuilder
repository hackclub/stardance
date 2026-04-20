json.extract! @devlog, :id, :body, :comments_count, :duration_seconds, :likes_count, :created_at, :updated_at

json.media @devlog.attachments.map { |attachment|
  {
    url: Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true),
    content_type: attachment.content_type
  }
}

json.comments @devlog.comments do |comment|
  json.extract! comment, :id, :body, :created_at, :updated_at

  json.author do
    json.extract! comment.user, :id, :display_name, :avatar
  end
end
