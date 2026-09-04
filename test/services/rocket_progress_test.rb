require "test_helper"

# The bar is derived, not stored, so these pin the rules that decide which
# approved hours it counts.
class RocketProgressTest < ActiveSupport::TestCase
  setup do
    @owner = create_user(slack_id: "U_ROCKET", display_name: "rocket-owner", verified: true)
    @in_window = RocketProgress::WINDOW_START + 1.day
  end

  test "counts approved hours synced inside the window" do
    synced_review(minutes: 120, at: @in_window)

    assert_in_delta 2.0, RocketProgress.snapshot.hours, 0.001
  end

  test "starts at zero by ignoring submissions synced before the window opens" do
    synced_review(minutes: 600, at: RocketProgress::WINDOW_START - 1.day)

    assert_in_delta 0.0, RocketProgress.snapshot.hours, 0.001
  end

  test "ignores submissions synced after the window closes" do
    synced_review(minutes: 600, at: RocketProgress::WINDOW_END + 1.day)

    assert_in_delta 0.0, RocketProgress.snapshot.hours, 0.001
  end

  test "ignores a review that never reached the unified base" do
    synced_review(minutes: 120, at: nil)

    assert_in_delta 0.0, RocketProgress.snapshot.hours, 0.001
  end

  test "counts reviewer-approved minutes rather than logged minutes" do
    synced_review(minutes: 120, approved: 30, at: @in_window)

    assert_in_delta 0.5, RocketProgress.snapshot.hours, 0.001
  end

  test "subtracts a fraud deduction the way the sync job does" do
    review = synced_review(minutes: 180, at: @in_window)
    deduct!(review, minutes: 60)

    assert_in_delta 2.0, RocketProgress.snapshot.hours, 0.001
  end

  test "a deduction larger than the approved time floors at zero rather than going negative" do
    counted = synced_review(minutes: 120, at: @in_window)
    over_deducted = synced_review(minutes: 60, at: @in_window)
    deduct!(over_deducted, minutes: 600)
    assert counted.persisted?

    assert_in_delta 2.0, RocketProgress.snapshot.hours, 0.001
  end

  test "leaves out a banned user's submission, as the sync job marks it rejected" do
    review = synced_review(minutes: 120, at: @in_window)
    review.user.update_columns(banned: true, banned_at: Time.current)

    assert_in_delta 0.0, RocketProgress.snapshot.hours, 0.001
  end

  test "leaves out a submission under the approved-minutes floor" do
    # Logged 20 minutes, but the reviewer only approved 5 — below the floor the
    # sync job rejects on.
    synced_review(minutes: 20, approved: 5, at: @in_window)

    assert_in_delta 0.0, RocketProgress.snapshot.hours, 0.001
  end

  test "reports progress against the 500 hour goal" do
    synced_review(minutes: 125 * 60, at: @in_window)

    assert_equal 500, RocketProgress.snapshot.goal_hours
    assert_equal 25, RocketProgress.snapshot.percent
    assert_in_delta 375.0, RocketProgress.snapshot.remaining_hours, 0.001
    assert_not RocketProgress.snapshot.complete?
  end

  test "caps the bar at 100 percent once the goal is met" do
    synced_review(minutes: 600 * 60, at: @in_window)

    assert_equal 100, RocketProgress.snapshot.percent
    assert_equal 0, RocketProgress.snapshot.remaining_hours
    assert RocketProgress.snapshot.complete?
  end

  private
    # An approved YSWS review with one reviewed devlog, synced to the unified
    # base at `at` (nil meaning it never got there).
    def synced_review(minutes:, at:, approved: nil, user: @owner)
      project = Project.create!(title: "Rocket #{SecureRandom.hex(4)}")
      project.memberships.create!(user: user, role: :owner)

      devlog = Post::Devlog.new(body: "work log", duration_seconds: minutes * 60)
      devlog.uploading_attachments = true
      devlog.save!
      Post.create!(project: project, user: user, postable: devlog)

      ship = Post::ShipEvent.new(body: "ship it")
      ship.uploading_attachments = true
      ship.save!
      Post.create!(project: project, user: user, postable: ship)

      review = Certification::Ysws.create!(user: user, project: project, post_ship_event: ship,
                                          original_minutes: minutes, reviewed_at: at,
                                          airtable_synced_at: at)
      Certification::Devlog
        .create!(post_devlog: devlog, ysws_review: review, original_minutes: minutes, status: :pending)
        .approve!(approved || minutes, "counted")
      review
    end

    def deduct!(review, minutes:)
      Certification::Integrity.create!(ship_event: review.post_ship_event,
                                       reviewer: @owner,
                                       status: :deducted,
                                       deduction_minutes: minutes)
    end
end
