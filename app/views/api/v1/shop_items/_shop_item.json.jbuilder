json.extract! item, :id, :name, :description, :ticket_cost, :one_per_person_ever, :limited, :created_at

json.available item.enabled_in_region?(user_region)
json.available_regions item.enabled_region_codes
json.image_url item.image.attached? ? rails_blob_path(item.image, only_path: true) : nil
json.categories item.shop_categories.map(&:slug)
