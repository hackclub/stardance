json.extract! user, :id, :display_name, :bio, :verification_status, :created_at
json.avatar_url user.avatar
json.i_follow api_followed_user_ids.include?(user.id)

# Private fields are only exposed on the key owner's own profile (/users/me),
# never when viewing another user via /users/{id} or search.
if user.id == @current_api_user&.id
  json.extract! user, :first_name, :last_name, :shop_region
  json.balance user.cached_balance
end
