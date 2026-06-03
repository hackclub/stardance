# == Schema Information
#
# Table name: project_follows
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  project_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_project_follows_on_project_id              (project_id)
#  index_project_follows_on_user_id                 (user_id)
#  index_project_follows_on_user_id_and_project_id  (user_id,project_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (user_id => users.id)
#
class ProjectFollow < ApplicationRecord
  belongs_to :user
  belongs_to :project

  validates :user_id, uniqueness: { scope: :project_id, message: "is already following this project" }
  validate :cannot_follow_own_project

  after_create_commit :send_gorse_follow_later

  private

  def send_gorse_follow_later
    send_gorse_feedback_later(user: user, item: project, feedback_type: :follow_project, timestamp: created_at)
  end

  def cannot_follow_own_project
    project_users = project.users

    if project_users.any? { |u| u.id == user_id }
      errors.add(:user_id, "cannot follow your own project")
    end
  end
end
