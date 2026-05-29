module User::ShopAccess
  # this needs more work
  extend ActiveSupport::Concern

  def seller? = ShopItem::HackClubberItem.exists?(user_id: id)

  def has_regions?
    regions.present? && regions.any?
  end

  def has_region?(region_code)
    regions.include?(region_code.to_s.upcase)
  end

  def regions_display
    regions.map { |region| Shop::Regionalizable.region_name(region) }.join(", ")
  end

  def reject_pending_orders!(reason: "User banned")
    shop_orders.where(aasm_state: %w[pending awaiting_periodical_fulfillment]).find_each do |order|
      order.mark_rejected(reason)
      order.save!
    end
  end

  DEV_ADDRESS = {
    "id" => "dev-address",
    "primary" => true,
    "first_name" => "Dev",
    "last_name" => "User",
    "line_1" => "15 Falls Road",
    "line_2" => nil,
    "city" => "Shelburne",
    "state" => "VT",
    "postal_code" => "05482",
    "country" => "US",
    "phone_number" => "+18025550100"
  }.freeze

  def addresses
    return [ DEV_ADDRESS ] if Rails.env.development?

    identity = hack_club_identity
    return [] unless identity&.access_token.present?

    identity_payload = HCAService.identity(identity.access_token)
    addresses = identity_payload["addresses"] || []
    phone_number = identity_payload["phone_number"]
    addresses.map { |address| address.merge("phone_number" => phone_number) }
  end

  def birthday
    identity = hack_club_identity
    return nil unless identity&.access_token.present?

    identity_payload = HCAService.identity(identity.access_token)
    birthday_str = identity_payload["birthday"]
    return nil if birthday_str.blank?

    Date.parse(birthday_str)
  rescue ArgumentError
    nil
  end
end
