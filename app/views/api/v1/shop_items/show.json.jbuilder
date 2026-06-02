json.partial! "api/v1/shop_items/shop_item", item: @item, user_region: @user_region

json.modifiers @item.available_modifiers_for_region(@user_region).map { |m|
  { id: m.id, name: m.name, group_name: m.group_name, ticket_cost: m.ticket_cost }
}
