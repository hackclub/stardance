json.extract! user, :id, :display_name, :first_name, :last_name, :bio, :verification_status, :shop_region, :created_at
json.avatar_url user.avatar
json.ticket_balance user.cached_balance
