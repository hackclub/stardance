require "test_helper"

# Hardware ships are certified by a reviewer against a timelapse rather than
# rated by peers, so they never enter the voting pool and don't wait on a vote
# count. Their owners are charged no vote debt either, and any debt they carry
# from software ships never holds a hardware payout.
class Post::HardwarePayoutTest < ActiveSupport::TestCase
  setup do
    Flipper.enable(:hardware_flow)
    Flipper.enable(:ship_event_payouts)
    @owner = create_user(slack_id: "U_HWP_OWNER", display_name: "hwp-owner")
  end

  teardown do
    Flipper.disable(:hardware_flow)
    Flipper.disable(:ship_event_payouts)
  end

  # --- voting pool ------------------------------------------------------------

  test "a hardware ship is never offered to a rater" do
    hardware = ship_for(hardware: true)
    software = ship_for(hardware: false)
    rater = create_user(slack_id: "U_HWP_RATER", display_name: "hwp-rater")

    offered = Vote::Matchmaker.new(rater).next_ship_event

    assert_not_equal hardware.id, offered&.id
    assert_equal software.id, offered&.id
  end

  # 48 assignments in production still pointed at hardware ships when it left
  # the pool; refresh only swapped a ship out once it was rejected or paid.
  test "an assignment handed out before hardware left the pool is replaced" do
    hardware = ship_for(hardware: true)
    software = ship_for(hardware: false)
    rater = create_user(slack_id: "U_HWP_STALE", display_name: "hwp-stale")
    stale = Vote::Assignment.create!(user: rater, ship_event: hardware, status: :assigned)

    refreshed = stale.refresh(Vote::Matchmaker.new(rater))

    assert_equal software.id, refreshed.ship_event_id
  end

  # --- payout gates -----------------------------------------------------------

  test "a hardware ship pays out on approval without any votes" do
    ship = ship_for(hardware: true)
    clear_vote_debt

    assert_difference -> { @owner.ledger_entries.count }, 1 do
      ship.issue_payout!
    end

    assert_operator ship.reload.payout, :>, 0
  end

  # refresh_payouts! is the only automated payout path, and it iterates the
  # ready_for_payout SCOPE - relaxing the instance-level gates alone left the
  # flat hardware payout unreachable in production.
  test "the automated sweep picks up a hardware ship with no votes" do
    ship = ship_for(hardware: true)
    clear_vote_debt

    assert_includes Post::ShipEvent.ready_for_payout.to_a, ship

    assert_difference -> { @owner.reload.ledger_entries.count }, 1 do
      Post::ShipEvent.refresh_payouts!
    end
  end

  test "the automated sweep still skips a software ship without votes" do
    ship = ship_for(hardware: false)
    clear_vote_debt

    assert_not_includes Post::ShipEvent.ready_for_payout.to_a, ship
  end

  test "the hardware payout is the flat rate times the hours" do
    ship = ship_for(hardware: true, hours: 3)
    clear_vote_debt

    ship.issue_payout!

    expected = 3 * Post::ShipEvent::Payouts::HARDWARE_STARDUST_PER_HOUR
    assert_equal expected, ship.reload.payout
  end

  test "a hardware ship does not wait out the payout review window" do
    ship = ship_for(hardware: true)
    clear_vote_debt

    ship.issue_payout!

    # Locked and paid in the same pass, unlike the voting path.
    assert_not_nil ship.reload.payout_basis_locked_at
    assert_not_nil ship.payout
  end

  # Debt carried over from a software ship is not the hardware builder's to work
  # off through this project, so it must not hold the build's payout.
  test "a hardware ship pays out while its owner is in vote debt" do
    ship = ship_for(hardware: true)
    @owner.update!(vote_balance: -Post::ShipEvent::VOTE_COST_PER_SHIP)

    assert_difference -> { @owner.ledger_entries.count }, 1 do
      ship.issue_payout!
    end

    assert_operator ship.reload.payout, :>, 0
  end

  test "shipping hardware charges no vote debt" do
    assert_no_difference -> { @owner.reload.vote_balance } do
      ship_for(hardware: true)
    end
  end

  test "shipping software still charges the vote debt" do
    assert_difference -> { @owner.reload.vote_balance }, -Post::ShipEvent::VOTE_COST_PER_SHIP do
      ship_for(hardware: false)
    end
  end

  # --- software is untouched --------------------------------------------------

  test "a software ship still waits for its votes" do
    ship = ship_for(hardware: false)
    clear_vote_debt

    assert_no_difference -> { @owner.ledger_entries.count } do
      ship.issue_payout!
    end

    assert_nil ship.reload.payout
  end

  private

  # reload first: the ship's after_commit already wrote the debt straight to the
  # DB, so assigning 0 to a stale in-memory 0 emits no UPDATE at all.
  def clear_vote_debt
    @owner.reload.update!(vote_balance: 0)
  end

  def ship_for(hardware:, hours: 2)
    project = Project.create!(title: "P #{SecureRandom.hex(4)}", created_at: 3.days.ago)
    Project::Membership.create!(project: project, user: @owner, role: :owner)
    project.update!(hardware_stage: "build") if hardware

    # `hours` is derived from devlogs in the ship window, not from hours_at_ship.
    devlog = Post::Devlog.new(body: "build log", duration_seconds: hours * 3600,
                              phase: (hardware ? "build" : nil))
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: @owner, postable: devlog, created_at: 1.hour.ago)

    # Both rows in one transaction so the ship's after_commit sees its Post -
    # decrement_user_vote_balance returns early without it.
    ship = Post::ShipEvent.new(body: "Ship it", uploading_attachments: true,
                               certification_status: "approved", hours_at_ship: hours)
    ActiveRecord::Base.transaction do
      ship.save!(validate: false)
      Post.create!(project: project, user: @owner, postable: ship, created_at: Time.current)
    end
    ship.update!(hours_at_ship: hours)
    # The ship was built before its Post existed, so its `post` association is
    # cached as nil - and payout_recipient reads through it.
    ship.reload
  end
end
