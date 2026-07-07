# == Schema Information
#
# Table name: lookout_sessions
#
#  id                     :bigint           not null, primary key
#  duration_seconds       :integer          default(0)
#  hackatime_forwarded_at :datetime
#  hackatime_project_name :string
#  hackatime_skipped      :boolean          default(FALSE), not null
#  mode                   :string
#  recording_url          :string
#  started_at             :datetime
#  status                 :string           default("pending")
#  stopped_at             :datetime
#  token                  :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  devlog_id              :bigint
#  project_id             :bigint           not null
#  user_id                :bigint           not null
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
  # Terminal states never change again, so the sync paths skip them.
  TERMINAL_STATUSES = %w[complete failed].freeze
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
  # Sessions that might still advance — everything not yet in a terminal state.
  # SyncPendingLookoutSessionsJob re-polls these so a recording can finalize even
  # when the builder closed the recorder tab before Lookout finished compiling.
  scope :syncable, -> { where.not(status: TERMINAL_STATUSES) }
  scope :unassigned, -> { where(status: "complete", hackatime_forwarded_at: nil, hackatime_skipped: false) }

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  # Mirror Lookout's client-API payload onto this row. The remote payload is
  # camelCase (trackedSeconds, videoUrl); tolerate snake_case too. Only accept a
  # status we recognize so update! can't blow up on a new remote state, and never
  # clobber an existing duration/video with a blank — Lookout returns a partial
  # payload while a session is still compiling. Returns self.
  def sync_from_remote!(remote)
    return self if remote.blank?

    next_status = remote[:status].presence_in(STATUSES)
    tracked = remote[:trackedSeconds] || remote[:tracked_seconds] || remote[:duration_seconds]
    video   = remote[:videoUrl] || remote[:video_url] || remote[:recording_url]

    update!(
      status: next_status || status,
      duration_seconds: tracked ? tracked.to_i : duration_seconds,
      recording_url: video.presence || recording_url
    )
    self
  end
end
