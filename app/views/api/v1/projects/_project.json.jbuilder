json.extract! project, :id, :title, :description, :ship_status, :project_type, :project_categories, :repo_url, :demo_url, :readme_url, :ai_declaration, :devlogs_count, :duration_seconds, :shipped_at, :created_at, :updated_at
json.devlog_ids project.devlogs.ids
json.banner_url project.banner.attached? ? rails_service_blob_path(project.banner, only_path: true) : nil
json.i_follow api_followed_project_ids.include?(project.id)
