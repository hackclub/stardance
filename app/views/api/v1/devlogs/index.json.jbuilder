json.devlogs @devlogs do |devlog|
  json.partial! "api/v1/devlogs/devlog", devlog: devlog
end

json.partial! "api/v1/pagination", pagy: @pagy
