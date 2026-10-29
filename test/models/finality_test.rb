require "test_helper"

class FinalityTest < ActiveSupport::TestCase
  setup do
    Flipper.enable(Finality::FEATURE_FLAG)
    @owner = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "finality#{SecureRandom.hex(4)}")
  end

  teardown do
    Flipper.disable(Finality::FEATURE_FLAG)
  end

  test "the ship day is judged in New York time" do
    # 03:00 UTC on the 28th is still 23:00 on the 27th in New York.
    ship_event = create_ship(shipped_at: Time.utc(2026, 10, 28, 3))

    assert_equal Date.new(2026, 10, 27), Finality.ship_day(ship_event)
    assert_equal 0.08, Finality.rate_for(ship_event)
  end

  test "ships outside the window are not listed and earn nothing" do
    before = create_ship(shipped_at: Time.utc(2026, 10, 27, 3), payout: 100)
    after = create_ship(shipped_at: Time.utc(2026, 11, 1, 5), payout: 100)

    assert_not_includes Finality.ships, before
    assert_not_includes Finality.ships, after
    assert_not Finality.award_bonus!(before)
    assert_not Finality.award_bonus!(after)
  end

  test "award_bonus! credits the day's share of the payout exactly once" do
    ship_event = create_ship(shipped_at: Time.utc(2026, 10, 29, 16), payout: 250)

    assert_difference -> { @owner.ledger_entries.count }, 1 do
      assert Finality.award_bonus!(ship_event)
      assert_not Finality.award_bonus!(ship_event)
    end

    entry = @owner.ledger_entries.last
    assert_equal 10, entry.amount
    assert_equal Finality::BONUS_CREATED_BY, entry.created_by
    assert_equal ship_event, entry.ledgerable
  end

  test "award_bonus! does nothing while the flag is off or before the payout" do
    paid = create_ship(shipped_at: Time.utc(2026, 10, 27, 16), payout: 100)
    unpaid = create_ship(shipped_at: Time.utc(2026, 10, 27, 17))

    Flipper.disable(Finality::FEATURE_FLAG)
    assert_not Finality.award_bonus!(paid)

    Flipper.enable(Finality::FEATURE_FLAG)
    assert_not Finality.award_bonus!(unpaid)
    assert_equal 0, @owner.ledger_entries.count
  end

  test "banned shippers earn no bonus and get no raffle entry" do
    ship_event = create_ship(shipped_at: Time.utc(2026, 10, 27, 16), payout: 100)
    @owner.update!(banned: true)

    assert_not Finality.award_bonus!(ship_event.reload)
    assert_not_includes Finality.raffle_entry_ids, ship_event.id
  end

  test "award_missing! catches up ships paid while the flag was off" do
    first = create_ship(shipped_at: Time.utc(2026, 10, 30, 16), payout: 300)
    second = create_ship(shipped_at: Time.utc(2026, 10, 31, 16), payout: 300)
    Finality.award_bonus!(first)

    assert_equal 1, Finality.award_missing!
    assert_equal 3, Finality.bonus_entry(second.reload).amount
  end

  test "each approved ship gets its own entry and rejected ships do not count" do
    rejected = create_ship(shipped_at: Time.utc(2026, 10, 27, 16), status: "rejected")
    first = create_ship(shipped_at: Time.utc(2026, 10, 28, 16))
    second = create_ship(shipped_at: Time.utc(2026, 10, 29, 16))

    entries = Finality.raffle_entry_ids

    assert_not_includes entries, rejected.id
    assert_includes entries, first.id
    assert_includes entries, second.id
  end

  test "pending and misfiled ships are excluded, and later approval or rejection updates entries" do
    pending = create_ship(shipped_at: Time.utc(2026, 10, 28, 16), status: "pending")
    misfiled = create_ship(shipped_at: Time.utc(2026, 10, 28, 17), status: "misfiled")

    assert_not_includes Finality.raffle_entry_ids, pending.id
    assert_not_includes Finality.raffle_entry_ids, misfiled.id
    assert_equal({ confirmed: 0, pending: 1 }, Finality.raffle_counts_for(@owner))

    travel_to Time.utc(2026, 11, 2) do
      pending.update!(certification_status: "approved")
      assert_includes Finality.raffle_entry_ids, pending.id
      assert_equal({ confirmed: 1, pending: 0 }, Finality.raffle_counts_for(@owner))
      pending.update!(certification_status: "rejected")
      assert_not_includes Finality.raffle_entry_ids, pending.id
      assert_equal({ confirmed: 0, pending: 0 }, Finality.raffle_counts_for(@owner))
    end
  end

  test "entry counts belong to the signed in shipper and honor exact window boundaries" do
    create_ship(shipped_at: Finality.window.begin - 1.second)
    create_ship(shipped_at: Finality.window.begin)
    create_ship(shipped_at: Finality.window.end - 1.second)
    create_ship(shipped_at: Finality.window.end)
    create_ship(shipped_at: Finality.window.begin + 1.hour, status: "pending")

    assert_equal({ confirmed: 2, pending: 1 }, Finality.raffle_counts_for(@owner))
    assert_equal({ confirmed: 0, pending: 0 }, Finality.raffle_counts_for(nil))
    assert_equal({ confirmed: 0, pending: 0 }, Finality.raffle_counts_for(users(:one)))
    @owner.update!(banned: true)
    assert_equal({ confirmed: 0, pending: 0 }, Finality.raffle_counts_for(@owner))
  end

  test "ships without a review status remain pending rather than disappearing" do
    ship = create_ship(shipped_at: Finality.window.begin + 1.hour, status: nil)
    assert_equal({ confirmed: 0, pending: 1 }, Finality.raffle_counts_for(@owner))
    assert_includes Finality.pending_raffle_ships, ship
    assert_not_includes Finality.approved_raffle_ships, ship
  end

  private

  def create_ship(shipped_at:, payout: nil, status: "approved")
    project = Project.create!(title: "Finality #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: @owner, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true, certification_status: status)
    Post.create!(project: project, user: @owner, postable: ship_event, created_at: shipped_at, updated_at: shipped_at)
    ship_event.update_columns(payout: payout) if payout
    ship_event.reload
  end
end
