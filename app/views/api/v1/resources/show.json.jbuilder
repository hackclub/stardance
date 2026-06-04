json.partial! "api/v1/resources/resource", resource: @resource
json.related_resources @resource.related_guides, partial: "api/v1/resources/resource", as: :resource
