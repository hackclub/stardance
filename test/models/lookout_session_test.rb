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
require "test_helper"

class LookoutSessionTest < ActiveSupport::TestCase
  setup do
    @user = create_user(slack_id: "U_LS", display_name: "ls_user")
    @project = Project.create!(title: "Robot arm", hardware_stage: "build")
    @project.memberships.create!(user: @user, role: :owner)
  end

  test "valid with a token and known status" do
    session = LookoutSession.new(user: @user, project: @project, token: "tok-1", status: "pending")
    assert session.valid?
  end

  test "requires a token" do
    session = LookoutSession.new(user: @user, project: @project, status: "pending")
    assert_not session.valid?
  end

  test "rejects an unknown status" do
    session = LookoutSession.new(user: @user, project: @project, token: "tok-2", status: "bogus")
    assert_not session.valid?
  end

  test "rejects an unknown mode" do
    session = LookoutSession.new(user: @user, project: @project, token: "tok-3", status: "pending", mode: "vr")
    assert_not session.valid?
  end

  test "token is unique" do
    LookoutSession.create!(user: @user, project: @project, token: "dup", status: "pending")
    dup = LookoutSession.new(user: @user, project: @project, token: "dup", status: "pending")
    assert_not dup.valid?
  end

  test "attachable scope returns stopped and complete sessions" do
    LookoutSession.create!(user: @user, project: @project, token: "p", status: "pending")
    complete = LookoutSession.create!(user: @user, project: @project, token: "c", status: "complete")
    stopped = LookoutSession.create!(user: @user, project: @project, token: "s", status: "stopped")

    assert_equal [ complete.id, stopped.id ].sort, LookoutSession.attachable.pluck(:id).sort
  end

  test "syncable scope excludes terminal (complete / failed) sessions" do
    pending = LookoutSession.create!(user: @user, project: @project, token: "sp", status: "pending")
    stopped = LookoutSession.create!(user: @user, project: @project, token: "ss", status: "stopped")
    LookoutSession.create!(user: @user, project: @project, token: "sc", status: "complete")
    LookoutSession.create!(user: @user, project: @project, token: "sf", status: "failed")

    assert_equal [ pending.id, stopped.id ].sort, LookoutSession.syncable.pluck(:id).sort
  end

  test "unassigned scope returns only complete sessions with no forwarded_at and not skipped" do
    # should appear
    unassigned = LookoutSession.create!(user: @user, project: @project, token: "ua1", status: "complete")
    # should NOT appear — forwarded
    LookoutSession.create!(user: @user, project: @project, token: "ua2", status: "complete",
                           hackatime_forwarded_at: Time.current, hackatime_project_name: "my-proj")
    # should NOT appear — skipped
    LookoutSession.create!(user: @user, project: @project, token: "ua3", status: "complete",
                           hackatime_skipped: true)
    # should NOT appear — not complete
    LookoutSession.create!(user: @user, project: @project, token: "ua4", status: "compiling")

    assert_equal [ unassigned.id ], LookoutSession.unassigned.pluck(:id)
  end

  test "unassigned scope excludes failed sessions" do
    LookoutSession.create!(user: @user, project: @project, token: "ua5", status: "failed")
    assert_empty LookoutSession.unassigned
  end

  test "terminal? is true only for complete and failed" do
    assert LookoutSession.new(status: "complete").terminal?
    assert LookoutSession.new(status: "failed").terminal?
    assert_not LookoutSession.new(status: "pending").terminal?
    assert_not LookoutSession.new(status: "stopped").terminal?
  end

  test "sync_from_remote! mirrors status, duration and video (camelCase)" do
    session = LookoutSession.create!(user: @user, project: @project, token: "sr1", status: "active", duration_seconds: 30)
    session.sync_from_remote!({ status: "complete", trackedSeconds: 600, videoUrl: "https://lookout.test/v/a" })

    assert_equal "complete", session.status
    assert_equal 600, session.duration_seconds
    assert_equal "https://lookout.test/v/a", session.recording_url
  end

  test "sync_from_remote! tolerates snake_case keys" do
    session = LookoutSession.create!(user: @user, project: @project, token: "sr2", status: "active")
    session.sync_from_remote!({ status: "complete", tracked_seconds: 120, recording_url: "https://lookout.test/v/b" })

    assert_equal 120, session.duration_seconds
    assert_equal "https://lookout.test/v/b", session.recording_url
  end

  test "sync_from_remote! never clobbers existing data with blanks or an unknown status" do
    session = LookoutSession.create!(user: @user, project: @project, token: "sr3", status: "compiling",
                                     duration_seconds: 300, recording_url: "https://lookout.test/v/keep")
    session.sync_from_remote!({ status: "garbage", videoUrl: "" })

    assert_equal "compiling", session.status
    assert_equal 300, session.duration_seconds
    assert_equal "https://lookout.test/v/keep", session.recording_url
  end

  test "sync_from_remote! is a no-op for a blank payload" do
    session = LookoutSession.create!(user: @user, project: @project, token: "sr4", status: "pending")
    assert_nothing_raised { session.sync_from_remote!(nil) }
    assert_equal "pending", session.status
  end
end
