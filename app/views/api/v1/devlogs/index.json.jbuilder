json.devlogs @devlogs, partial: "api/v1/devlogs/devlog", as: :devlog
json.pagination { json.partial! "api/v1/pagination", pagy: @pagy }
