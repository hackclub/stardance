require "test_helper"

class Certification::ShipApprovalMessageTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @owner = create_user(slack_id: "U_APPROVAL_OWNER", display_name: "approvalowner")
    @reviewer = create_user(slack_id: "U_APPROVAL_REV", display_name: "approvalrev")
    @project = Project.create!(title: "Approval #{SecureRandom.hex(4)}")
    @project.memberships.create!(user: @owner, role: :owner)
    @mission = create_mission
    @project.mission_attachments.create!(mission: @mission)
  end

  test "approval DM says the ship is out for voting on the voting path" do
    submission = ship_to_mission!(@project, @owner, @mission)

    dm = approval_dm_for(submission)

    assert_includes dm[:message], "out for voting"
    assert dm[:locals][:goes_to_voting]
  end

  test "approval DM doesn't promise voting for a static prize mission" do
    submission = ship_to_mission!(@project, @owner, @mission)
    submission.update!(payout_path: "static_prize")

    dm = approval_dm_for(submission)

    assert_not_includes dm[:message], "voting"
    assert_not dm[:locals][:goes_to_voting]
  end

  private

  def approval_dm_for(submission)
    cert = @project.ship_reviews.create!(status: :pending, post_ship_event: submission.ship_event)
    clear_enqueued_jobs

    cert.update!(status: :approved, reviewer: @reviewer)

    job = enqueued_jobs.find { |j| j["job_class"] == "SendSlackDmJob" }
    assert job, "expected an approval DM to be enqueued"
    args = ActiveJob::Arguments.deserialize(job["arguments"])
    { message: args[1], locals: args[2][:locals] }
  end
end
