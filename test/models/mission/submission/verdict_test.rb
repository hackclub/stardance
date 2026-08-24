require "test_helper"

class Mission::Submission::VerdictTest < ActiveSupport::TestCase
  setup do
    @reviewer = User.create!(email: "v-reviewer-#{SecureRandom.hex(4)}@example.test",
                             display_name: "v-reviewer-#{SecureRandom.hex(4)}",
                             slack_id: "U#{SecureRandom.hex(8)}")
    @builder = User.create!(email: "v-builder-#{SecureRandom.hex(4)}@example.test",
                            display_name: "v-builder-#{SecureRandom.hex(4)}",
                            slack_id: "U#{SecureRandom.hex(8)}")
    @project = Project.create!(title: "Verdict Test Project")
    @project.memberships.create!(user: @builder, role: :owner)
    @mission = create_mission
    @submission = ship_to_mission!(@project, @builder, @mission, status: "pending")
  end

  test "a verdict erased by a re-review request is read back from the version that erased it" do
    reject!(@submission, "Needs a real README")
    erase_verdict!(@submission)

    verdicts = Mission::Submission::Verdict.history_for(@project, excluding: @submission)

    assert_equal 1, verdicts.size
    assert_equal "rejected", verdicts.first.status
    assert_equal "Needs a real README", verdicts.first.feedback
    assert_equal @reviewer, verdicts.first.reviewer
    assert_equal @mission, verdicts.first.mission
  end

  test "repeated re-reviews of one submission each leave a verdict behind" do
    3.times do |round|
      reject!(@submission, "Round #{round} feedback")
      erase_verdict!(@submission)
    end

    verdicts = Mission::Submission::Verdict.history_for(@project, excluding: @submission)

    assert_equal 3, verdicts.size
    # Newest decision first.
    assert_equal [ "Round 2 feedback", "Round 1 feedback", "Round 0 feedback" ], verdicts.map(&:feedback)
  end

  # A certification failure clears the same columns but was never anyone's
  # judgement, so it is not history a reviewer should be shown.
  test "a certification failure is not surfaced as a verdict" do
    @submission.update!(rejection_message: Post::ShipEvent::UNCERTIFIED_SUBMISSION_MESSAGE)
    @submission.update_column(:status, "rejected")
    @submission.update!(rejection_message: nil)
    @submission.update_column(:status, "pending")

    assert_empty Mission::Submission::Verdict.history_for(@project, excluding: @submission)
  end

  private

  def reject!(submission, feedback)
    submission.update!(reviewed_by: @reviewer, reviewed_at: Time.current, rejection_message: feedback)
    submission.update_column(:status, "rejected")
  end

  # What Projects::MissionResubmissionsController does: clear the verdict, then
  # send the row back to the queue.
  def erase_verdict!(submission)
    submission.update!(reviewed_by: nil, reviewed_at: nil, rejection_message: nil,
                       claimed_at: nil, claim_expires_at: nil)
    submission.update_column(:status, "pending")
  end
end
