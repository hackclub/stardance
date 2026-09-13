require "test_helper"

# The bar is derived, not stored, so these pin the rules that decide which
# approved hours it counts.
class RocketProgressTest < ActiveSupport::TestCase
  setup do
    @owner = create_user(slack_id: "U_ROCKET", display_name: "rocket-owner", verified: true)
    @in_window = RocketProgress::WINDOW_START + 1.day
  end

  test "counts approved hours whose ship landed inside the window" do
    reviewed_ship(minutes: 120, at: @in_window)

    assert_in_delta 2.0, RocketProgress.snapshot.hours, 0.001
  end

  test "starts at zero by ignoring ships posted before the window opens" do
    reviewed_ship(minutes: 600, at: RocketProgress::WINDOW_START - 1.day)

    assert_in_delta 0.0, RocketProgress.snapshot.hours, 0.001
  end

  test "ignores ships posted after the window closes" do
    reviewed_ship(minutes: 600, at: RocketProgress::WINDOW_END + 1.day)

    assert_in_delta 0.0, RocketProgress.snapshot.hours, 0.001
  end

  test "counts reviewer-approved minutes rather than logged minutes" do
    reviewed_ship(minutes: 120, approved: 30, at: @in_window)

    assert_in_delta 0.5, RocketProgress.snapshot.hours, 0.001
  end

  test "subtracts a fraud deduction the way the sync job does" do
    review = reviewed_ship(minutes: 180, at: @in_window)
    deduct!(review, minutes: 60)

    assert_in_delta 2.0, RocketProgress.snapshot.hours, 0.001
  end

  test "a deduction larger than the approved time floors at zero rather than going negative" do
    counted = reviewed_ship(minutes: 120, at: @in_window)
    over_deducted = reviewed_ship(minutes: 60, at: @in_window)
    deduct!(over_deducted, minutes: 600)
    assert counted.persisted?

    assert_in_delta 2.0, RocketProgress.snapshot.hours, 0.001
  end

  test "leaves out a banned user's submission, as the sync job marks it rejected" do
    review = reviewed_ship(minutes: 120, at: @in_window)
    review.user.update_columns(banned: true, banned_at: Time.current)

    assert_in_delta 0.0, RocketProgress.snapshot.hours, 0.001
  end

  test "leaves out a submission under the approved-minutes floor" do
    # Logged 20 minutes, but the reviewer only approved 5 — below the floor the
    # sync job rejects on.
    reviewed_ship(minutes: 20, approved: 5, at: @in_window)

    assert_in_delta 0.0, RocketProgress.snapshot.hours, 0.001
  end

  test "reports progress against the 5000 hour goal" do
    reviewed_ship(minutes: 1250 * 60, at: @in_window)

    assert_equal 5000, RocketProgress.snapshot.goal_hours
    assert_equal 25, RocketProgress.snapshot.percent
    assert_in_delta 3750.0, RocketProgress.snapshot.remaining_hours, 0.001
    assert_not RocketProgress.snapshot.complete?
  end

  test "caps the bar at 100 percent once the goal is met" do
    reviewed_ship(minutes: 6000 * 60, at: @in_window)

    assert_equal 100, RocketProgress.snapshot.percent
    assert_equal 0, RocketProgress.snapshot.remaining_hours
    assert RocketProgress.snapshot.complete?
  end

  private
    # An approved YSWS review with one reviewed devlog, whose ship event was
    # posted (created_at) at `at` — the timestamp RocketProgress windows
    # against, so the bar moves as soon as the ship lands and gets reviewed
    # rather than waiting on a separate Airtable sync.
    def reviewed_ship(minutes:, at:, approved: nil, user: @owner)
      project = Project.create!(title: "Rocket #{SecureRandom.hex(4)}")
      project.memberships.create!(user: user, role: :owner)

      devlog = Post::Devlog.new(body: "work log", duration_seconds: minutes * 60)
      devlog.uploading_attachments = true
      devlog.save!
      Post.create!(project: project, user: user, postable: devlog)

      ship = Post::ShipEvent.new(body: "ship it", created_at: at)
      ship.uploading_attachments = true
      ship.save!
      Post.create!(project: project, user: user, postable: ship, created_at: at)

      review = Certification::Ysws.create!(user: user, project: project, post_ship_event: ship,
                                          original_minutes: minutes, reviewed_at: at)
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
