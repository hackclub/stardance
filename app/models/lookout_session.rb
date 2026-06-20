# == Schema Information
#
# Table name: lookout_sessions
#
#  id               :bigint           not null, primary key
#  duration_seconds :integer          default(0)
#  mode             :string
#  recording_url    :string
#  started_at       :datetime
#  status           :string           default("pending")
#  stopped_at       :datetime
#  token            :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  devlog_id        :bigint
#  project_id       :bigint           not null
#  user_id          :bigint           not null
#
# Indexes
#
#  index_lookout_sessions_on_devlog_id              (devlog_id)
#  index_lookout_sessions_on_project_id             (project_id)
#  index_lookout_sessions_on_project_id_and_status  (project_id,status)
#  index_lookout_sessions_on_token                  (token) UNIQUE
#  index_lookout_sessions_on_user_id                (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (devlog_id => post_devlogs.id)
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (user_id => users.id)
#
class LookoutSession < ApplicationRecord
  STATUSES = %w[pending active paused stopped compiling complete failed].freeze
  # How the session was recorded (desktop / web / camera).
  MODES = %w[desktop web camera].freeze

  belongs_to :user
  belongs_to :project

  belongs_to :devlog, class_name: "Post::Devlog", optional: true

  validates :token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }, allow_nil: true

  scope :for_project, ->(project) { where(project: project) }
  scope :attachable, -> { where(status: %w[stopped complete]) }
end
