json.resources @resources, partial: "api/v1/resources/resource", as: :resource
json.categories Guide.category_order do |category|
  json.slug category
  json.label Guide.category_label(category)
end
