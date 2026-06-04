json.extract! mission, :id, :slug, :name, :description, :difficulty,
              :estimated_completion_minutes, :steps_count, :prizes_count,
              :start_at, :end_at, :featured_at, :achievement_name,
              :created_at, :updated_at
json.status mission.index_bucket
json.available mission.available_at?
json.icon_url mission.icon.attached? ? rails_blob_path(mission.icon, only_path: true) : nil
json.banner_url mission.banner.attached? ? rails_blob_path(mission.banner, only_path: true) : nil
