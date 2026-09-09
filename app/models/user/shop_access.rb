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
    shop_orders.where(aasm_state: ShopOrder::REJECTABLE_STATES).find_each do |order|
      order.system_rejection = true
      order.internal_rejection_reason = reason
      order.mark_rejected(reason)
      order.save!
    end
  end

  def addresses
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
