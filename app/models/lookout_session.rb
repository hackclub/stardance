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
# Historical record of a Lookout recording. Stardance stopped recording with
# Lookout when hardware time moved to Lapse, so nothing starts these rows any
# more; they exist so the ~7.3k finished recordings already attached to projects
# stay viewable on the hardware review pages (see LookoutService). The temporary
# session-finalize recovery flow (see LookoutSessionsController) still syncs a
# row from Lookout so a stranded builder can push its time to Hackatime.
class LookoutSession < ApplicationRecord
  STATUSES = %w[pending active paused stopped compiling complete failed].freeze
  # Terminal states never change again, so the sync path skips them.
  TERMINAL_STATUSES = %w[complete failed].freeze
  # How the session was recorded (desktop / web / camera).
  MODES = %w[desktop web camera].freeze
  # The temporary recovery window (finalize page + /my/timelapses) closes after
  # this; past it the surfaces send builders back to Lapse. See
  # Projects::LookoutSessionsController and My::TimelapsesController.
  FINALIZE_DEADLINE = Time.utc(2026, 8, 14, 23, 59, 59)

  # Sessions carrying capture time worth sending to Hackatime.
  scope :recoverable, -> { where("duration_seconds > 0") }

  belongs_to :user
  belongs_to :project

  validates :token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }, allow_nil: true

  # Sessions that got far enough to have something worth showing a reviewer.
  scope :attachable, -> { where(status: %w[stopped complete]) }

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  # Mirror Lookout's client-API payload onto this row. The remote payload is
  # camelCase (trackedSeconds, videoUrl); tolerate snake_case too. Only accept a
  # status we recognize so update! can't blow up on a new remote state, and never
  # clobber an existing duration/video with a blank. Returns self.
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
