# == Schema Information
#
# Table name: user_notification_preferences
#
#  id             :bigint           not null, primary key
#  category       :string           not null
#  email_enabled  :boolean
#  in_app_enabled :boolean
#  slack_enabled  :boolean
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_user_notification_preferences_on_user_id               (user_id)
#  index_user_notification_preferences_on_user_id_and_category  (user_id,category) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class User::NotificationPreference < ApplicationRecord
  self.table_name = "user_notification_preferences"

  belongs_to :user

  validates :category, presence: true, uniqueness: { scope: :user_id }
end
