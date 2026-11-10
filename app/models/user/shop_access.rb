module User::ShopAccess
  # this needs more work
  extend ActiveSupport::Concern

  # Midnight Eastern at the end of 9 November 2026.
  SHOP_CLOSES_AT = Time.find_zone!("America/New_York").local(2026, 11, 10)
  # How long the shop stays open after someone's last payout lands.
  SHOP_CLOSE_GRACE = 24.hours
  PAYOUT_LEDGER_SOURCES = [ "ship_event_payout", Virality::ReconcileBonus::CREATED_BY ].freeze

  def seller? = ShopItem::HackClubberItem.exists?(user_id: id)

  # Admins can keep the shop open for someone with the shop_unlocked flag.
  def shop_closed?
    return false if Flipper.enabled?(:shop_unlocked, self)

    closes_at = shop_closes_at
    closes_at.present? && !closes_at.future?
  end

  # nil while a ship or virality payout is still on its way.
  def shop_closes_at
    return if awaiting_payout?

    [ SHOP_CLOSES_AT, last_payout_at&.+(SHOP_CLOSE_GRACE) ].compact.max
  end

  def awaiting_payout?
    awaiting_ship_payout? || awaiting_virality_payout?
  end

  def last_payout_at
    ledger_entries.where(created_by: PAYOUT_LEDGER_SOURCES).where("amount > 0").maximum(:created_at)
  end

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

    identity_payload = identity.hca_identity
    addresses = identity_payload["addresses"] || []
    phone_number = identity_payload["phone_number"]
    addresses.map { |address| address.merge("phone_number" => phone_number) }
  end

  def birthday
    identity = hack_club_identity
    return nil unless identity&.access_token.present?

    identity_payload = identity.hca_identity
    birthday_str = identity_payload["birthday"]
    return nil if birthday_str.blank?

    Date.parse(birthday_str)
  rescue ArgumentError
    nil
  end

  private

  # Ships still in the cert queue, or approved and not yet paid. Static-prize
  # mission ships never get a stardust payout, so they don't count.
  def awaiting_ship_payout?
    Post::ShipEvent.joins(:post)
      .where(posts: { user_id: id }, certification_status: %w[pending approved])
      .unpaid
      .voting_payout_path
      .exists?
  end

  def awaiting_virality_payout?
    ProjectMention.awaiting_review.where(project_id: memberships.select(:project_id)).exists?
  end
end
