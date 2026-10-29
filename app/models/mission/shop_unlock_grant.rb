# == Schema Information
#
# Table name: mission_shop_unlock_grants
#
#  id            :bigint           not null, primary key
#  reason        :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  granted_by_id :bigint           not null
#  mission_id    :bigint           not null
#  user_id       :bigint           not null
#
# Indexes
#
#  index_mission_shop_unlock_grants_on_granted_by_id           (granted_by_id)
#  index_mission_shop_unlock_grants_on_mission_id              (mission_id)
#  index_mission_shop_unlock_grants_on_mission_id_and_user_id  (mission_id,user_id) UNIQUE
#  index_mission_shop_unlock_grants_on_user_id                 (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (granted_by_id => users.id)
#  fk_rails_...  (mission_id => missions.id)
#  fk_rails_...  (user_id => users.id)
#
# An admin unlocking a mission's shop items for one user without an approved
# submission, e.g. when their ship missed the mission. Only lifts the shop
# lock (ShopItem#mission_locked_for?); it does not complete the mission.
class Mission::ShopUnlockGrant < ApplicationRecord
  has_paper_trail

  belongs_to :mission
  belongs_to :user
  belongs_to :granted_by, class_name: "User"

  validates :user_id, uniqueness: { scope: :mission_id }
end
