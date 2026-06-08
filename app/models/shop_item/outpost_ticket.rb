# == Schema Information
#
# Table name: shop_items
#
#  id                                :bigint           not null, primary key
#  accessory_tag                     :string
#  agh_contents                      :jsonb
#  blocked_countries                 :string           default([]), is an Array
#  buyable_by_self                   :boolean          default(TRUE)
#  default_assigned_user_id_au       :bigint
#  default_assigned_user_id_ca       :bigint
#  default_assigned_user_id_eu       :bigint
#  default_assigned_user_id_in       :bigint
#  default_assigned_user_id_uk       :bigint
#  default_assigned_user_id_us       :bigint
#  default_assigned_user_id_xx       :bigint
#  description                       :string
#  draft                             :boolean          default(FALSE), not null
#  enabled                           :boolean
#  enabled_au                        :boolean
#  enabled_ca                        :boolean
#  enabled_eu                        :boolean
#  enabled_in                        :boolean
#  enabled_uk                        :boolean
#  enabled_until                     :datetime
#  enabled_us                        :boolean
#  enabled_xx                        :boolean
#  hacker_score                      :integer
#  hcb_category_lock                 :string
#  hcb_keyword_lock                  :string
#  hcb_merchant_lock                 :string
#  hcb_one_time_use                  :boolean          default(FALSE)
#  hcb_preauthorization_instructions :text
#  internal_description              :string
#  limited                           :boolean
#  long_description                  :text
#  max_qty                           :integer
#  mission_prize_only                :boolean          default(FALSE), not null
#  name                              :string
#  one_per_person_ever               :boolean
#  past_purchases                    :integer          default(0)
#  payout_percentage                 :integer          default(0)
#  required_ships_count              :integer          default(1)
#  required_ships_end_date           :date
#  required_ships_start_date         :date
#  requires_achievement              :string           default([]), is an Array
#  requires_ship                     :boolean          default(FALSE)
#  requires_verification_call        :boolean          default(FALSE), not null
#  sale_percentage                   :integer
#  show_image_in_shop                :boolean          default(FALSE)
#  show_in_carousel                  :boolean
#  site_action                       :integer
#  source_region                     :string
#  special                           :boolean
#  stock                             :integer
#  ticket_cost                       :integer
#  type                              :string
#  unlisted                          :boolean          default(FALSE)
#  unlock_on                         :date
#  usd_cost                          :decimal(, )
#  usd_offset_au                     :decimal(10, 2)
#  usd_offset_ca                     :decimal(10, 2)
#  usd_offset_eu                     :decimal(10, 2)
#  usd_offset_in                     :decimal(10, 2)
#  usd_offset_uk                     :decimal(10, 2)
#  usd_offset_us                     :decimal(10, 2)
#  usd_offset_xx                     :decimal(10, 2)
#  created_at                        :datetime         not null
#  updated_at                        :datetime         not null
#  created_by_user_id                :bigint
#  default_assigned_user_id          :bigint
#  user_id                           :bigint
#
# Indexes
#
#  index_shop_items_on_created_by_user_id        (created_by_user_id)
#  index_shop_items_on_default_assigned_user_id  (default_assigned_user_id)
#  index_shop_items_on_mission_prize_only        (mission_prize_only)
#  index_shop_items_on_user_id                   (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (default_assigned_user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id)
#
# The Outpost Ticket: locked behind the "presentable hardware project" flag and
# discounted per-user by the Stardust accrued from unrequested funding dollars.
class ShopItem::OutpostTicket < ShopItem
  # Effective price = base price minus the user's accrued Outpost discount,
  # floored at 0. The overflow past the base becomes a flight stipend
  # (see User::Wallet#outpost_flight_stipend).
  def price_for_user(user, region)
    base = price_for_region(region)
    return base unless user

    [ 0, base - user.outpost_discount_stardust.to_i ].max
  end
end
