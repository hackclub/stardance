json.extract! user, :id, :display_name, :bio, :verification_status, :created_at
json.avatar_url user.avatar
json.banner_url user.banner.attached? ? rails_blob_path(user.banner.blob, only_path: true) : nil
json.i_follow api_followed_user_ids.include?(user.id)

if user.id == @current_api_user&.id
  json.extract! user, :first_name, :last_name, :shop_region
  json.balance user.cached_balance
end
