require "test_helper"

# Exercises the full-auto reversal of a decided hardware review. Every HCB call
# is stubbed - this class touches real grant money, so the suite must never
# reach a live API.
class Certification::ReviewUndoerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # A card grant that has NOT been spent: balance still equals the amount.
  def unspent_grant(hashid: "cdg_test", amount_cents: 6_000)
    Hashie::Mash.new("id" => hashid, "status" => "active",
                     "amount_cents" => amount_cents, "balance_cents" => amount_cents,
                     "disbursements" => [])
  end

  # A card grant that has been partially spent: balance below the amount.
  def spent_grant(hashid: "cdg_test", amount_cents: 6_000, balance_cents: 1_000)
    Hashie::Mash.new("id" => hashid, "status" => "active",
                     "amount_cents" => amount_cents, "balance_cents" => balance_cents,
                     "disbursements" => [ { "transaction_id" => "txn_1" } ])
  end

  setup do
    Flipper.enable(:hardware_flow)
    @owner = create_user(slack_id: "U_UNDO_OWNER", display_name: "undo-owner", verified: true)
    @reviewer = create_user(slack_id: "U_UNDO_REV", display_name: "undo-rev")
    @reviewer.grant_role!(:admin)
    @project = Project.create!(title: "Undo HW #{SecureRandom.hex(4)}", hardware_stage: "design")
    @project.memberships.create!(user: @owner, role: :owner)
    add_devlog(@project, "design")
  end

  # ---- funding request preflight -----------------------------------------

  test "preflight marks an unspent grant as reversible and the review as undoable" do
    fr = approved_funding_with_grant
    pf = HCBService.stub(:show_card_grant, unspent_grant) do
      Certification::ReviewUndoer.new(fr).preflight
    end

    assert pf.undoable?, "an approved, unspent funding request should be undoable"
    grant = pf.effects.find { |e| e.effect == :hcb_grant }
    assert_equal :reverse, grant.action
    stage = pf.effects.find { |e| e.effect == :project_stage }
    assert_equal :reverse, stage.action
  end

  test "preflight blocks a review whose grant has been spent" do
    fr = approved_funding_with_grant
    pf = HCBService.stub(:show_card_grant, spent_grant) do
      Certification::ReviewUndoer.new(fr).preflight
    end

    assert_not pf.undoable?
    grant = pf.effects.find { |e| e.effect == :hcb_grant }
    assert_equal :block, grant.action
    assert pf.blockers.any?
  end

  test "preflight blocks a superseded (non-latest) funding request" do
    old = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 3_000, status: :pending
    )
    old.update!(reviewer: @reviewer, status: :returned, feedback: "redo")
    # Resubmit supersedes the returned one.
    @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 3_000, status: :pending
    )

    pf = Certification::ReviewUndoer.new(old).preflight
    assert_not pf.undoable?
    assert pf.effects.any? { |e| e.effect == :latest && e.action == :block }
  end

  test "preflight records the owner notification as a correction, not an unsend" do
    fr = approved_funding_with_grant
    pf = HCBService.stub(:show_card_grant, unspent_grant) do
      Certification::ReviewUndoer.new(fr).preflight
    end

    note = pf.effects.find { |e| e.effect == :notifications }
    assert_equal :correction, note.action
  end

  test "preflight blocks a claimed design kit" do
    fr = approved_kit_funding
    redeem_kit!(fr)

    pf = Certification::ReviewUndoer.new(fr).preflight
    assert_not pf.undoable?
    kit = pf.effects.find { |e| e.effect == :design_kit }
    assert_equal :block, kit.action
  end

  # ---- funding request undo! ---------------------------------------------

  test "undo! reverses an approved funding request and records paper_trail" do
    fr = approved_funding_with_grant
    versions_before = fr.versions.count

    cancelled = nil
    result = HCBService.stub(:show_card_grant, unspent_grant) do
      HCBService.stub(:cancel_card_grant!, ->(hashid:) { cancelled = hashid; { "status" => "canceled" } }) do
        Certification::ReviewUndoer.new(fr, actor: @reviewer).undo!
      end
    end

    assert result.undone?
    assert_equal "cdg_test", cancelled, "the unspent grant must be cancelled"

    fr.reload
    assert fr.pending?
    assert_nil fr.decided_at
    assert_nil fr.reviewer_id
    assert_nil fr.stardust_earned
    assert_nil fr.hcb_grant_hashid, "clearing the hashid lets a re-approval issue a fresh grant"
    assert fr.reversed_at.present?, "the review is marked reversed for the history badge"
    assert_equal "design", @project.reload.hardware_stage
    assert_operator fr.versions.count, :>, versions_before, "the reversal must be paper_trailed"
  end

  test "deciding a reversed funding request again clears the reversal marker" do
    fr = approved_funding_with_grant
    HCBService.stub(:show_card_grant, unspent_grant) do
      HCBService.stub(:cancel_card_grant!, ->(hashid:) { { "status" => "canceled" } }) do
        Certification::ReviewUndoer.new(fr, actor: @reviewer).undo!
      end
    end
    assert fr.reload.reversed_at.present?

    HCBService.stub(:create_card_grant, { "id" => "cdg_new" }) do
      fr.update!(reviewer: @reviewer, status: :approved)
    end

    assert_nil fr.reload.reversed_at, "a fresh verdict clears the reversal marker"
  end

  test "undo! refuses a spent grant and leaves the review approved" do
    fr = approved_funding_with_grant

    cancel_called = false
    result = HCBService.stub(:show_card_grant, spent_grant) do
      HCBService.stub(:cancel_card_grant!, ->(hashid:) { cancel_called = true }) do
        Certification::ReviewUndoer.new(fr, actor: @reviewer).undo!
      end
    end

    assert_not result.undone?
    assert_not cancel_called, "a spent grant must never be cancelled"
    assert fr.reload.approved?, "a blocked undo must leave the verdict intact"
    assert_equal "build", @project.reload.hardware_stage
  end

  test "undo! of a returned funding request touches no grant and leaves the stage alone" do
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 3_000, status: :pending
    )
    fr.update!(reviewer: @reviewer, status: :returned, feedback: "needs work")

    grant_touched = false
    result = HCBService.stub(:show_card_grant, ->(*) { grant_touched = true }) do
      HCBService.stub(:cancel_card_grant!, ->(**) { grant_touched = true }) do
        Certification::ReviewUndoer.new(fr, actor: @reviewer).undo!
      end
    end

    assert result.undone?
    assert_not grant_touched, "a returned request never had a grant"
    assert fr.reload.pending?
    assert_equal "design", @project.reload.hardware_stage
  end

  test "undo! notifies the owner of the reversal" do
    fr = approved_funding_with_grant

    assert_difference -> { @owner.notifications.where(type: "Notifications::Hardware::ReviewUndone").count }, 1 do
      HCBService.stub(:show_card_grant, unspent_grant) do
        HCBService.stub(:cancel_card_grant!, ->(hashid:) { { "status" => "canceled" } }) do
          Certification::ReviewUndoer.new(fr, actor: @reviewer).undo!
        end
      end
    end
  end

  test "undo! refuses a superseded (non-latest) funding request" do
    old = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 3_000, status: :pending
    )
    old.update!(reviewer: @reviewer, status: :returned, feedback: "redo")
    @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 2, requested_amount_cents: 3_000, status: :pending
    )

    result = Certification::ReviewUndoer.new(old, actor: @reviewer).undo!

    assert_not result.undone?
    assert old.reload.returned?, "a superseded review is left exactly as it was"
  end

  # ---- caching + lock window ---------------------------------------------

  test "preflight caches the grant lookup so repeated renders don't re-hit HCB" do
    fr = approved_funding_with_grant
    calls = 0

    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      HCBService.stub(:show_card_grant, ->(hashid:) { calls += 1; unspent_grant }) do
        2.times { Certification::ReviewUndoer.new(fr).preflight }
      end
    end

    assert_equal 1, calls, "the grant status should be fetched once and served from cache after"
  end

  test "undo! does not cancel the grant when the lock-time re-check fails" do
    fr = approved_funding_with_grant
    undoer = Certification::ReviewUndoer.new(fr, actor: @reviewer)
    cancel_called = false

    result = HCBService.stub(:show_card_grant, unspent_grant) do
      HCBService.stub(:cancel_card_grant!, ->(hashid:) { cancel_called = true }) do
        undoer.stub(:still_undoable?, false) do
          undoer.undo!
        end
      end
    end

    assert_not result.undone?
    assert_not cancel_called, "the grant must not be cancelled once the lock-time re-check fails"
    assert fr.reload.approved?, "a re-check failure leaves the verdict intact"
    assert_equal "build", @project.reload.hardware_stage
  end

  # ---- ship undo! --------------------------------------------------------

  test "undo! reverses an approved ship and deletes the auto-created YSWS review" do
    cert, ship_event = approved_ship

    assert @project.reload.ship_status == "approved"
    assert_equal "approved", ship_event.reload.certification_status
    ysws = Certification::Ysws.find_by(ship_cert_id: cert.id)
    assert ysws, "approving a ship should have created a YSWS review"

    result = Certification::ReviewUndoer.new(cert, actor: @reviewer).undo!

    assert result.undone?
    # Withdrawn, not pending: the ship leaves the reviewer queue and the pending
    # guards so the builder re-submits rather than the reviewer re-deciding.
    assert cert.reload.withdrawn?, "the undone ship review is withdrawn, not left pending"
    assert_equal "pending", ship_event.reload.certification_status
    assert_equal "draft", @project.reload.ship_status, "the project is un-submitted, not auto-queued"
    assert_nil @project.shipped_at, "shipped_at is cleared so the ship reads as withdrawn"
    assert_not @project.awaiting_ship_review?, "no pending review remains to block a manual re-ship"
    assert_nil Certification::Ysws.find_by(id: ysws.id), "the auto-created YSWS review should be gone"
  end

  test "undo! blocks a ship whose hardware mission rewards were granted" do
    cert = approved_hardware_mission_ship

    pf = Certification::ReviewUndoer.new(cert).preflight
    assert_not pf.undoable?
    reward = pf.effects.find { |e| e.effect == :mission_reward }
    assert_equal :block, reward.action

    result = Certification::ReviewUndoer.new(cert, actor: @reviewer).undo!
    assert_not result.undone?
    assert cert.reload.approved?
  end

  private

  def add_devlog(project, phase)
    devlog = Post::Devlog.new(body: "log", duration_seconds: 3600, phase: phase)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project: project, user: @owner, postable: devlog)
  end

  def approved_funding_with_grant
    fr = @project.certification_funding_requests.create!(
      user: @owner, complexity_tier: 3, requested_amount_cents: 6_000, status: :pending
    )
    HCBService.stub(:create_card_grant, { "id" => "cdg_test" }) do
      fr.update!(reviewer: @reviewer, status: :approved, feedback: "great")
    end
    fr.reload
  end

  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  def approved_kit_funding
    mission = create_mission
    mission.update!(hardware: true)
    kit = ShopItem.new(name: "Kit #{SecureRandom.hex(3)}", description: "kit",
                       ticket_cost: 0, type: "ShopItem::ThirdPartyPhysical", enabled: true, mission_prize_only: true)
    kit.image.attach(io: StringIO.new(PIXEL_PNG), filename: "kit.png", content_type: "image/png")
    kit.save!
    mission.prizes.create!(shop_item: kit, position: 0, category: :after_design)
    @project.mission_attachments.create!(mission: mission)
    @kit_item = kit

    fr = @project.certification_funding_requests.create!(user: @owner, status: :pending)
    fr.update!(reviewer: @reviewer, status: :approved)
    fr.reload
  end

  # Places a free order for the kit and records the redemption against the
  # funding request, standing in for a builder actually claiming their kit.
  # The order is saved without validation - the shop's order validations are
  # not what this test exercises, only that a redemption exists.
  def redeem_kit!(funding_request)
    order = ShopOrder.new(
      user: @owner, shop_item: @kit_item, quantity: 1,
      frozen_item_price: 0, frozen_address: { "line_1" => "1 St", "country" => "US" }
    )
    order.save!(validate: false)
    Mission::PrizeRedemption.record!(shop_order: order, gate: funding_request)
  end

  def approved_ship
    project = Project.create!(title: "Ship HW #{SecureRandom.hex(4)}", hardware_stage: "build")
    project.memberships.create!(user: @owner, role: :owner)
    @project = project
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true, hours_at_ship: 5)
    Post.create!(project: project, user: @owner, postable: ship_event)
    project.update_columns(ship_status: "submitted", shipped_at: Time.current)
    cert = project.ship_reviews.create!(status: :pending, post_ship_event: ship_event)
    cert.update!(status: :approved, reviewer: @reviewer)
    [ cert.reload, ship_event ]
  end

  def approved_hardware_mission_ship
    project = Project.create!(title: "MissionShip #{SecureRandom.hex(4)}", hardware_stage: "build")
    project.memberships.create!(user: @owner, role: :owner)
    @project = project
    mission = create_mission
    mission.update!(hardware: true, achievement_name: "Done")
    project.mission_attachments.create!(mission: mission)
    ship_event = Post::ShipEvent.create!(body: "Shipped!", uploading_attachments: true, hours_at_ship: 3)
    project.posts.create!(user: @owner, postable: ship_event)
    project.update_columns(ship_status: "submitted", shipped_at: Time.current)
    submission = Mission::Submission.create!(ship_event: ship_event, mission: mission, payout_path: "voting")
    cert = project.ship_reviews.create!(status: :pending, post_ship_event: ship_event)
    cert.update!(status: :approved, reviewer: @reviewer)
    assert submission.reload.approved?, "setup: hardware mission submission should be approved"
    cert.reload
  end
end
