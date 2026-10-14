require "test_helper"

# What the Guardian of Integrity left on a ship. A fraud deduction comes off the
# approved figure rather than the claimed one, so the fraud subject page shows it
# beside the tracked time an integrity verdict is about to adjust.
class Certification::YswsGoiHoursTest < ActiveSupport::TestCase
  include UserFactory

  setup { @user = create_user(slack_id: "u-goi", display_name: "goishipper") }

  test "a decided review reports what it cut the claim down to" do
    review = reviewed_review(claimed: 1200, approved: 450)

    assert_equal 20.0, review.claimed_hours
    assert_equal 7.5, review.approved_hours
    assert_predicate review, :marked_down?
  end

  test "a review that approved everything is not a markdown" do
    review = reviewed_review(claimed: 300, approved: 300)

    assert_equal 5.0, review.approved_hours
    assert_not_predicate review, :marked_down?
  end

  test "a review still in the queue has no hours to report yet" do
    review = reviewed_review(claimed: 600, approved: 120)
    review.update_columns(reviewed_at: nil)

    assert_nil review.reload.approved_hours
    assert_not_predicate review, :marked_down?, "nothing is marked down until a verdict lands"
  end

  test "the totals come off the devlog reviews, not the queue's sort column" do
    review = reviewed_review(claimed: 600, approved: 300)
    review.update_columns(original_minutes: 9999)

    assert_equal 10.0, review.reload.claimed_hours
  end

  test "a rejected devlog counts as nothing approved" do
    review = reviewed_review(claimed: 600, approved: 0, status: :rejected)

    assert_equal 0.0, review.approved_hours
    assert_predicate review, :marked_down?
  end

  test "an integrity check reaches the review on its own ship event" do
    review = reviewed_review(claimed: 600, approved: 300)
    check = Certification::Integrity.create!(ship_event: review.post_ship_event, status: :pending)

    assert_equal review, check.ysws_review
  end

  test "a ship event nobody has reviewed for YSWS has no review to reach" do
    check = Certification::Integrity.create!(ship_event: ship_on(project_with_membership), status: :pending)

    assert_nil check.ysws_review
  end

  private

  def project_with_membership
    project = Project.create!(title: "GOI #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: @user, role: :owner)
    project
  end

  # Built before the Post exists so Post::ShipEvent's shippability validation has
  # no project to check, matching how the other ship-event suites do it.
  def ship_on(project)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: @user, postable: ship_event)
    ship_event
  end

  def reviewed_review(claimed:, approved:, status: :approved)
    project = project_with_membership
    review = Certification::Ysws.create!(
      user: @user, project: project, post_ship_event: ship_on(project),
      original_minutes: claimed, reviewer: @user, reviewed_at: Time.current
    )

    devlog = Post::Devlog.new(body: "Devlog", duration_seconds: claimed * 60)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: @user, postable: devlog)

    review.devlog_reviews.create!(post_devlog_id: devlog.id, original_minutes: claimed,
                                  approved_minutes: approved, status: status,
                                  justification: "Reviewed")
    review.reload
  end
end
