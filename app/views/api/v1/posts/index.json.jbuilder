json.posts @posts, partial: "api/v1/posts/post", as: :post
json.pagination { json.partial! "api/v1/pagination", pagy: @pagy }
