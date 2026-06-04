json.extract! user, :id, :display_name, :first_name, :last_name, :bio, :verification_status, :shop_region, :created_at
json.avatar_url user.avatar
json.balance user.cached_balance
json.i_follow api_followed_user_ids.include?(user.id)
