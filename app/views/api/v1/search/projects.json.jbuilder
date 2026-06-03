json.projects @projects, partial: "api/v1/projects/project", as: :project
json.pagination { json.partial! "api/v1/pagination", pagy: @pagy }
