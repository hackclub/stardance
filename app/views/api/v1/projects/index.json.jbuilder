json.projects @projects do |project|
  json.partial! "api/v1/projects/project", project: project
end

json.pagination do
  json.current_page @pagy.page
  json.total_pages @pagy.pages
  json.total_count @pagy.count
  json.next_page @pagy.next
end
