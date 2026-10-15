require "test_helper"

class StickerPromoTest < ActiveSupport::TestCase
  setup do
    @user = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "star#{SecureRandom.hex(4)}")
  end

  test "weeks_for returns the numbers of every week the user shipped in" do
    ship_in_week(1)
    ship_in_week(3)

    assert_equal [ 1, 3 ], @user.free_sticker_weeks
  end

  test "weeks_for is empty when the user shipped outside every window" do
    ship_at(StickerPromo::WEEKS.first.window_start - 1.day)
    ship_at(StickerPromo::WEEKS.last.deadline + 1.day)

    assert_empty @user.free_sticker_weeks
  end

  test "weeks_for ignores ships on soft-deleted projects" do
    project = ship_in_week(2)
    project.update!(deleted_at: Time.current)

    assert_empty @user.free_sticker_weeks
  end

  test "weeks 1 and 2 meet without overlapping" do
    assert_equal StickerPromo::WEEKS.first.deadline, StickerPromo::WEEKS.second.window_start

    ship_at(StickerPromo::WEEKS.second.window_start - 1.hour)

    assert_equal [ 1 ], @user.free_sticker_weeks
  end

  test "a week defaults to opening seven days before its deadline" do
    week = StickerPromo::WEEKS.last

    assert_equal week.deadline - 7.days, week.window_start
  end

  test "weeks_for reads ship events, not the reship-overwritten shipped_at" do
    project = ship_in_week(1)
    project.update!(shipped_at: StickerPromo::WEEKS.last.deadline + 1.week)

    assert_equal [ 1 ], @user.free_sticker_weeks
  end

  test "the deadline constants track the last week in the registry" do
    assert_equal StickerPromo::WEEKS.last.deadline, StickerPromo::DEADLINE
    assert_equal StickerPromo::WEEKS.last.label, StickerPromo::DEADLINE_LABEL
    assert_equal StickerPromo::WEEKS.last.window_start, StickerPromo.window_start
  end

  private

  def ship_in_week(number)
    week = StickerPromo::WEEKS.find { |w| w.number == number }
    ship_at(week.window_start + 1.hour)
  end

  def ship_at(time)
    project = Project.create!(title: "Ship #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: @user, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    post = Post.create!(project: project, user: @user, postable: ship_event)
    post.update_column(:created_at, time)
    project
  end
end
