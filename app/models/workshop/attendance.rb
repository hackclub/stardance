# == Schema Information
#
# Table name: workshop_attendances
#
#  id          :bigint           not null, primary key
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :bigint           not null
#  workshop_id :bigint           not null
#
# Indexes
#
#  index_workshop_attendances_on_user_id                  (user_id)
#  index_workshop_attendances_on_workshop_id_and_user_id  (workshop_id,user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#  fk_rails_...  (workshop_id => workshops.id)
#
class Workshop::Attendance < ApplicationRecord
  self.table_name = "workshop_attendances"

  belongs_to :workshop
  belongs_to :user

  # No uniqueness validation: create_or_find_by! needs the DB index's raw
  # RecordNotUnique, not a validation error.
end
