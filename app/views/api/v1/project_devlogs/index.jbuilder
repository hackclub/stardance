json.devlogs @devlogs do |devlog|
  json.extract! devlog, :id, :body, :comments_count, :duration_seconds, :likes_count, :created_at, :updated_at

  json.media devlog.attachments.map {
    |attachment| {
      url: Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true),
      content_type: attachment.content_type
    }
}

  json.comments devlog.comments do |comment|
    json.extract! comment, :id, :body, :created_at, :updated_at

    json.author do
      json.extract! comment.user, :id, :display_name, :avatar
    end
  end
end

json.pagination do
  json.current_page @pagy.page
  json.total_pages @pagy.pages
  json.total_count @pagy.count
  json.next_page @pagy.next
end
