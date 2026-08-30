# == Schema Information
#
# Table name: extension_usages
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  project_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_extension_usages_on_project_id                 (project_id)
#  index_extension_usages_on_project_id_and_created_at  (project_id,created_at)
#  index_extension_usages_on_user_id                    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (user_id => users.id)
#
class ExtensionUsage < ApplicationRecord
  belongs_to :project
  belongs_to :user

  def self.weekly_unique_users_for(project_ids)
    return {} if project_ids.blank?

    where(project_id: project_ids)
      .where("created_at >= ?", 1.week.ago)
      .group(:project_id)
      .count("DISTINCT user_id")
  end
end
