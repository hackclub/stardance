json.extract! project, :id, :title, :description, :ship_status,
                       :repo_url, :demo_url, :readme_url, :ai_declaration,
                       :created_at, :updated_at

json.devlog_ids project.devlog_posts.map(&:postable_id)

json.banner_url project.banner.attached? ? rails_blob_url(project.banner) : nil
json.banner_thumb_url project.banner.attached? ? rails_representation_url(project.banner.variant(:thumb)) : nil

# Fabricate imports a moved project for whoever signs in there with this Slack ID.
if (transfer = project.fabricate_transfer)
  json.fabricate_transfer do
    json.moved_at transfer.created_at
    json.owner { json.extract! transfer.user, :id, :slack_id, :display_name, :bio }
  end
else
  json.fabricate_transfer nil
end
