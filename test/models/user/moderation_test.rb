require "test_helper"

# Banning has to clear every order the user still has in flight. Held and
# awaiting-verification orders used to survive the ban and sit in the fraud
# queue forever, since nothing else ever revisits them.
class User::ModerationTest < ActiveSupport::TestCase
  include UserFactory
  include ActiveJob::TestHelper

  SYNC_JOB = Certification::YswsAirtableSyncJob

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @user = create_user(slack_id: "u-banned", display_name: "banme", verified: true)
    @user.update!(has_gotten_free_stickers: true)
    @item = build_item
  end

  test "banning rejects orders in every state a rejection can reach" do
    orders = ShopOrder::REJECTABLE_STATES.index_with { |state| place_order(state) }

    @user.ban!(reason: "test")

    orders.each do |state, order|
      assert_equal "rejected", order.reload.aasm_state, "order left in #{state} after ban"
      assert_equal "test", order.rejection_reason
    end
  end

  test "banning leaves settled orders alone" do
    fulfilled = place_order("fulfilled")

    @user.ban!(reason: "test")

    assert_equal "fulfilled", fulfilled.reload.aasm_state
  end

  test "banning resyncs a finished review the unified base has not taken" do
    review = completed_review

    assert_enqueued_with(job: SYNC_JOB, args: [ review.id ]) do
      @user.ban!(reason: "test")
    end
  end

  test "unbanning resyncs so the rejection comes back off the row" do
    review = completed_review
    @user.ban!(reason: "test")

    assert_enqueued_with(job: SYNC_JOB, args: [ review.id ]) do
      @user.unban!
    end
  end

  test "banning leaves a review the unified base already took alone" do
    review = completed_review
    review.update_column(:in_unified_db, "recStubUnified01")

    assert_no_enqueued_jobs(only: SYNC_JOB) do
      @user.ban!(reason: "test")
    end
  end

  test "banning leaves a review still in the queue to the rejector" do
    pending_review

    assert_no_enqueued_jobs(only: SYNC_JOB) do
      @user.ban!(reason: "test")
    end
  end

  private

  def completed_review
    project, ship_event = project_with_ship

    Certification::Ysws.create!(
      user: @user,
      project: project,
      post_ship_event: ship_event,
      original_minutes: 120,
      reviewer: @user,
      reviewed_at: Time.current,
      airtable_synced_at: Time.current
    )
  end

  def pending_review
    project, ship_event = project_with_ship

    Certification::Ysws.create!(
      user: @user,
      project: project,
      post_ship_event: ship_event,
      original_minutes: 120
    )
  end

  def project_with_ship
    project = Project.create!(title: "Ship #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: @user, role: :owner)

    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: @user, postable: ship_event)

    [ project, ship_event ]
  end

  def place_order(state)
    order = @user.shop_orders.create!(shop_item: @item, quantity: 1, frozen_address: { "country" => "US" })
    order.update_column(:aasm_state, state)
    order
  end

  def build_item
    item = ShopItem.new(
      name: "Test Patch #{SecureRandom.hex(4)}",
      description: "A cheap physical item",
      ticket_cost: 0,
      usd_cost: 7,
      type: "ShopItem::ThirdPartyPhysical",
      enabled: true
    )
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end
end
