require "test_helper"

# The builder's project feed interleaves devlog posts, ship decisions, and
# funding reviews. A returned funding review has to keep its chronological place
# so it scrolls down as newer devlogs are posted, rather than only the latest
# review ever showing (see Project#timeline_funding_requests and
# Project.sort_timeline_entries).
class ProjectTimelineTest < ActiveSupport::TestCase
  setup do
    Flipper.enable(:hardware_flow)
    @owner = create_user(slack_id: "U_PTL_OWNER", display_name: "ptlowner", verified: true)
    @project = Project.create!(title: "Rover PTL", hardware_stage: "design")
    @project.memberships.create!(user: @owner, role: :owner)

    devlog = Post::Devlog.new(body: "first log", duration_seconds: 3600, phase: "design")
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: @project, user: @owner, postable: devlog)
  end

  test "sort_timeline_entries orders a returned review below a later devlog and above an earlier one" do
    earlier_devlog = Post.new(created_at: 3.days.ago)
    # Created before the earlier devlog, but decided after it: the decided_at is
    # what places the review, so it must land between the two devlogs.
    returned_review = Certification::FundingRequest.new(
      created_at: 4.days.ago, decided_at: 2.days.ago, status: :returned
    )
    later_devlog = Post.new(created_at: 1.day.ago)

    ordered = Project.sort_timeline_entries([ earlier_devlog, returned_review, later_devlog ])

    assert_equal [ later_devlog, returned_review, earlier_devlog ], ordered
    assert_operator ordered.index(later_devlog), :<, ordered.index(returned_review),
                    "a later devlog should sit above the returned review"
    assert_operator ordered.index(returned_review), :<, ordered.index(earlier_devlog),
                    "the returned review should sit above the devlog that predates its decision"
  end

  test "timeline_sort_key uses decided_at for a decided review, falling back to created_at while pending" do
    decided = Certification::FundingRequest.new(created_at: 5.days.ago, decided_at: 1.day.ago)
    pending = Certification::FundingRequest.new(created_at: 2.days.ago, decided_at: nil)

    assert_equal decided.decided_at, Project.timeline_sort_key(decided)
    assert_equal pending.created_at, Project.timeline_sort_key(pending)
  end

  test "timeline_funding_requests keeps older reviews, not just the latest" do
    older = create_pending_request
    older.update_column(:status, funding_status(:returned))

    newer = create_pending_request
    newer.update_column(:status, funding_status(:returned))

    requests = @project.timeline_funding_requests.to_a

    assert_includes requests, older, "an older returned review must stay on the timeline"
    assert_includes requests, newer
  end

  test "timeline_funding_requests surfaces pending, approved and returned but omits misfiled and withdrawn" do
    request = create_pending_request

    %i[pending approved returned].each do |status|
      request.update_column(:status, funding_status(status))
      assert_includes @project.timeline_funding_requests.to_a, request,
                      "a #{status} review belongs on the timeline"
    end

    %i[misfiled withdrawn].each do |status|
      request.update_column(:status, funding_status(status))
      assert_not_includes @project.timeline_funding_requests.to_a, request,
                          "a #{status} review is surfaced elsewhere, not on the timeline"
    end
  end

  private

  def create_pending_request
    @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 3_000, status: :pending
    )
  end

  def funding_status(name)
    Certification::FundingRequest.statuses.fetch(name.to_s)
  end
end
