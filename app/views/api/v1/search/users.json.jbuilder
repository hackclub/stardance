json.users @users, partial: "api/v1/users/user", as: :user
json.pagination { json.partial! "api/v1/pagination", pagy: @pagy }
