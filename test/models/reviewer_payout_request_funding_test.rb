require "test_helper"

# Funding-request reviews pay reviewers the same way ship reviews do.
class ReviewerPayoutRequestFundingTest < ActiveSupport::TestCase
  test "total_earned_for includes funding review bounties" do
    reviewer = User.create!(
      email: "rev-#{SecureRandom.hex(6)}@example.com",
      display_name: "Rev#{SecureRandom.hex(3)}",
      slack_id: "U#{SecureRandom.hex(8)}"
    )
    owner = User.create!(
      email: "owner-#{SecureRandom.hex(6)}@example.com",
      display_name: "Owner#{SecureRandom.hex(3)}",
      slack_id: "U#{SecureRandom.hex(8)}"
    )
    project = Project.create!(title: "HW #{SecureRandom.hex(4)}", hardware_stage: "design")
    Project::Membership.create!(project: project, user: owner, role: :owner)

    assert_equal 0, ReviewerPayoutRequest.total_earned_for(reviewer)

    fr = project.certification_funding_requests.create!(
      user: owner, complexity_tier: 1, requested_amount_cents: 2_500, status: :pending
    )
    fr.update!(reviewer: reviewer, status: :approved)

    assert_equal Certification::FundingRequest::REVIEW_BOUNTY, ReviewerPayoutRequest.total_earned_for(reviewer)
  end
end
