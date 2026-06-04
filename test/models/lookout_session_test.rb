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
#  project_id       :bigint           not null
#  user_id          :bigint           not null
#
# Indexes
#
#  index_lookout_sessions_on_project_id             (project_id)
#  index_lookout_sessions_on_project_id_and_status  (project_id,status)
#  index_lookout_sessions_on_token                  (token) UNIQUE
#  index_lookout_sessions_on_user_id                (user_id)
#
# Foreign Keys
#
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
end
