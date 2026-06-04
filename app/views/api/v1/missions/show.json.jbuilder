json.partial! "api/v1/missions/mission", mission: @mission

json.steps @steps do |step|
  json.id step.id
  json.title step.title
  json.position step.position
end

json.prizes @prizes do |prize|
  json.id prize.id
  json.position prize.position
  json.shop_item do
    item = prize.shop_item
    json.id item.id
    json.name item.name
    json.image_url item.image.attached? ? rails_blob_path(item.image, only_path: true) : nil
  end
end
