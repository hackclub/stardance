json.by_balance @by_balance.each_with_index do |user, i|
  json.rank i + 1
  json.id user.id
  json.display_name user.display_name
  json.avatar_url user.avatar
  json.balance user.approx_balance
end

json.by_total_earned @by_total_earned.each_with_index do |user, i|
  json.rank i + 1
  json.id user.id
  json.display_name user.display_name
  json.avatar_url user.avatar
  json.total_earned user.approx_total_earned
end

json.my_rank do
  json.balance @balance_rank
  json.total_earned @total_earned_rank
end
