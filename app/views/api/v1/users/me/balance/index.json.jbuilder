json.stardust_balance @balance

json.ledger @entries do |entry|
  json.extract! entry, :id, :amount, :reason, :created_at
end

json.pagination do
  json.partial! "api/v1/pagination", pagy: @pagy
end
