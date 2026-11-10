require "test_helper"

class User::ShopAccessTest < ActiveSupport::TestCase
  include UserFactory

  CLOSES_AT = User::ShopAccess::SHOP_CLOSES_AT

  setup do
    @user = create_user(slack_id: "U_SHOP_CLOSE", display_name: "shop_close")
    @project = Project.create!(title: "Closing project")
    @project.memberships.create!(user: @user, role: :owner)
  end

  teardown do
    Flipper.disable(:shop_unlocked)
  end

  test "the shop is open until the deadline" do
    travel_to(CLOSES_AT - 1.minute) { assert_not_predicate @user, :shop_closed? }
    travel_to(CLOSES_AT) { assert_predicate @user, :shop_closed? }
  end

  test "a payout in the last day before the deadline keeps the shop open for 24 hours" do
    paid_at = CLOSES_AT - 2.hours
    travel_to(paid_at) { pay(@user, "ship_event_payout") }

    travel_to(paid_at + 23.hours) { assert_not_predicate @user, :shop_closed? }
    travel_to(paid_at + 24.hours) { assert_predicate @user, :shop_closed? }
  end

  test "a pending ship keeps the shop open until 24 hours after it pays out" do
    ship = create_ship("pending")
    travel_to(CLOSES_AT + 3.days) { assert_not_predicate @user, :shop_closed? }

    paid_at = CLOSES_AT + 4.days
    travel_to(paid_at) do
      ship.update!(certification_status: "approved", payout: 10)
      pay(@user, "ship_event_payout")
    end

    travel_to(paid_at + 23.hours) { assert_not_predicate @user, :shop_closed? }
    travel_to(paid_at + 24.hours) { assert_predicate @user, :shop_closed? }
  end

  test "a returned ship doesn't keep the shop open" do
    create_ship("returned")

    travel_to(CLOSES_AT) { assert_predicate @user, :shop_closed? }
  end

  test "a virality mention awaiting review keeps the shop open" do
    mention = ProjectMention.create!(project: @project, url: "https://example.com/post")
    travel_to(CLOSES_AT + 1.day) { assert_not_predicate @user, :shop_closed? }

    paid_at = CLOSES_AT + 2.days
    travel_to(paid_at) do
      mention.update!(approved_at: Time.current, approved_tier: "good")
      pay(@user, Virality::ReconcileBonus::CREATED_BY)
    end

    travel_to(paid_at + 23.hours) { assert_not_predicate @user, :shop_closed? }
    travel_to(paid_at + 24.hours) { assert_predicate @user, :shop_closed? }
  end

  test "an admin unlock keeps the shop open" do
    Flipper.enable(:shop_unlocked, @user)

    travel_to(CLOSES_AT + 1.day) { assert_not_predicate @user, :shop_closed? }
  end

  private

  def create_ship(status)
    ship = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true, certification_status: status, hours_at_ship: 1)
    Post.create!(project: @project, user: @user, postable: ship)
    ship
  end

  def pay(user, source)
    user.ledger_entries.create!(ledgerable: @project, amount: 10, reason: "Payout", created_by: source)
  end
end
