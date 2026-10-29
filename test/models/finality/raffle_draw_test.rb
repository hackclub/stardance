require "test_helper"

# == Schema Information
#
# Table name: finality_raffle_draws
#
#  id                :bigint           not null, primary key
#  entry_count       :integer          default(0), not null
#  frozen_at         :datetime
#  key               :string           not null
#  participant_count :integer          default(0), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  frozen_by_id      :bigint
#
# Indexes
#
#  index_finality_raffle_draws_on_frozen_by_id  (frozen_by_id)
#  index_finality_raffle_draws_on_key           (key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (frozen_by_id => users.id)
#
class Finality::RaffleDrawTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    travel_to Finality.window.end + 1.day
    @admin = users(:one)
    @admin.grant_role!(:admin)
    @project = projects(:one)
    @people = 8.times.map do |i|
      create_user(slack_id: "U_DRAW_#{i}", display_name: "raffle_draw_#{i}", hca_linked: false)
    end
    @ships = @people.map { |person| create_ship(person) }
    2.times { @ships << create_ship(@people.first) }
  end

  teardown { travel_back }

  test "pool records exact ships once with an audited admin and excludes ineligible entries" do
    create_ship(@people.first, status: "rejected")
    create_ship(@people.first, status: "misfiled")
    create_ship(@people.first, shipped_at: Finality.window.end)
    @people.last.update!(banned: true)
    create_ship(@people.last, status: "pending")

    draw = freeze_pool
    assert_equal 9, draw.entry_count
    assert_equal 7, draw.participant_count
    assert_equal @ships.map(&:id) - [ @ships[7].id ], draw.entries.pluck(:ship_event_id)
    assert_equal @admin.id, draw.frozen_by_id
    version = draw.versions.find_by!(event: "freeze_raffle_pool")
    assert_equal @admin.id.to_s, version.whodunnit
    assert_equal draw.id, freeze_pool.id
    assert_equal 9, draw.entries.count
  end

  test "cannot freeze before close or while reviews remain" do
    travel_to Finality.window.end - 1.second do
      assert_raises(Finality::RaffleDraw::Error) { freeze_pool }
    end
    pending = create_ship(@people.first, status: "pending")
    assert_raises(Finality::RaffleDraw::Error) { freeze_pool }
    assert_nil Finality::RaffleDraw.current
    pending.update!(certification_status: "approved")
    assert_equal 11, freeze_pool.entry_count
  end

  test "empty pools cannot freeze and nonadmins cannot mutate" do
    @ships.each { |ship| ship.update!(certification_status: "rejected") }
    assert_raises(Finality::RaffleDraw::Error) { freeze_pool }
    assert_raises(Finality::RaffleDraw::Error) { Finality::RaffleDraw.freeze_pool!(actor: @people.first) }
  end

  test "weighted selection uses all approved ships and removes winners from subsequent weights" do
    draw = freeze_pool
    totals = []
    SecureRandom.stub(:random_number, ->(total) { totals << total; 2 }) do
      assert_equal 2, draw.roll!(prize_key: "vip", actor: @admin)
    end
    assert_equal [ 10, 7 ], totals
    first = draw.selections.find_by!(prize_key: "vip", slot: 1)
    assert_equal @people.first.id, first.user_id
    assert_equal 3, first.entry_count
    assert_equal 10, first.pool_entry_count
    assert_equal @admin.id.to_s, first.versions.last.whodunnit
  end

  test "ticket at the first user's weight boundary selects the next user" do
    draw = freeze_pool
    SecureRandom.stub(:random_number, 3) { draw.roll!(prize_key: "vip", actor: @admin) }
    assert_equal @people.second.id, draw.selections.find_by!(slot: 1).user_id
  end

  test "every prize slot is unique across prizes and repeated roll is idempotent" do
    58.times do |i|
      create_ship(create_user(slack_id: "U_MORE_#{i}", display_name: "more_#{i}", hca_linked: false))
    end
    draw = freeze_pool
    Finality::RAFFLE_PRIZES.each do |prize|
      assert_equal prize[:quantity], draw.roll!(prize_key: prize[:key], actor: @admin)
      assert_equal 0, draw.roll!(prize_key: prize[:key], actor: @admin)
    end
    slots = Finality::RAFFLE_PRIZES.sum { |prize| prize[:quantity] }
    assert_equal slots, draw.selections.active.count
    assert_equal slots, draw.selections.active.distinct.count(:user_id)
  end

  test "later approvals do not expand a frozen pool and new bans or rejections reduce weights" do
    draw = freeze_pool
    late_person = create_user(slack_id: "U_LATE_DRAW", display_name: "late_draw", hca_linked: false)
    create_ship(late_person)
    @people.second.update!(banned: true)
    @ships[2].update!(certification_status: "misfiled")
    @ships[3].post.destroy!
    @ships.last.update!(certification_status: "rejected")

    counts = draw.available_entry_counts
    assert_equal 2, counts.fetch(@people.first.id)
    [ late_person, *@people[1..3] ].each { |person| assert_not counts.key?(person.id) }
    assert_equal 10, draw.reload.entry_count
  end

  test "reroll persists reason and actor, permanently excluding the prior selection" do
    draw = freeze_pool
    draw.roll!(prize_key: "vip", actor: @admin)
    previous = draw.selections.first
    replacement = draw.reroll!(selection_id: previous.id, reason: "Prior fraud finding reviewed by staff", actor: @admin)

    assert_equal previous.slot, replacement.slot
    assert_equal previous.prize_key, replacement.prize_key
    assert_not_equal previous.user_id, replacement.user_id
    assert_equal 2, draw.selections.active.count
    assert_equal 3, draw.selections.count
    assert_equal @admin.id, previous.reload.voided_by_id
    assert_equal "Prior fraud finding reviewed by staff", previous.void_reason
    version = previous.versions.find_by!(event: "reroll_raffle_selection")
    assert_equal @admin.id.to_s, version.whodunnit
    assert_not draw.available_entry_counts.key?(previous.user_id)
    assert_not previous.user.reload.banned?
    assert_raises(Finality::RaffleDraw::Error) do
      draw.reroll!(selection_id: previous.id, reason: "Stale browser retry", actor: @admin)
    end
    assert_equal 3, draw.selections.count
  end

  test "reroll needs a reason and keeps the current result if replacements are exhausted" do
    draw = freeze_pool
    draw.roll!(prize_key: "artemis", actor: @admin)
    draw.roll!(prize_key: "xbox", actor: @admin) # uses up everyone left in the pool
    previous = draw.selections.first
    [ " ", "x" * 1001, "No eligible replacement" ].each do |reason|
      assert_raises(Finality::RaffleDraw::Error) { draw.reroll!(selection_id: previous.id, reason: reason, actor: @admin) }
    end
    assert_nil previous.reload.voided_at
    assert_equal @people.size, draw.selections.active.count
  end

  test "failed replacement rolls back the old result and its audit history" do
    draw = freeze_pool
    draw.roll!(prize_key: "vip", actor: @admin)
    previous = draw.selections.first
    versions = previous.versions.count
    SecureRandom.stub(:random_number, ->(_) { raise "random source unavailable" }) do
      assert_raises(RuntimeError) { draw.reroll!(selection_id: previous.id, reason: "Review", actor: @admin) }
    end
    assert_nil previous.reload.voided_at
    assert_equal versions, previous.versions.count
    assert_equal 2, draw.selections.active.count
  end

  test "draws only save internal results, with no jobs, notifications, payouts or orders" do
    clear_enqueued_jobs
    assert_no_enqueued_jobs do
      assert_no_difference [ "Notification.count", "LedgerEntry.count", "ShopOrder.count" ] do
        draw = freeze_pool
        draw.roll!(prize_key: "vip", actor: @admin)
        draw.reroll!(selection_id: draw.selections.first.id, reason: "Manual review", actor: @admin)
      end
    end
  end

  test "invalid prize, unprepared draw and unauthorized actor cannot draw" do
    draw = Finality::RaffleDraw.create!(key: Finality::RaffleDraw::KEY)
    assert_raises(Finality::RaffleDraw::Error) { draw.roll!(prize_key: "vip", actor: @admin) }
    draw = freeze_pool
    assert_raises(Finality::RaffleDraw::Error) { draw.roll!(prize_key: "made-up", actor: @admin) }
    assert_raises(Finality::RaffleDraw::Error) { draw.roll!(prize_key: "vip", actor: @people.first) }
    assert_equal 0, draw.selections.count
  end

  private

  def freeze_pool
    Finality::RaffleDraw.freeze_pool!(actor: @admin)
  end

  def create_ship(user, status: "approved", shipped_at: Finality.window.begin + 1.hour)
    ship = Post::ShipEvent.create!(body: "Raffle test ship", uploading_attachments: true, certification_status: status)
    Post.create!(project: @project, user: user, postable: ship, created_at: shipped_at, updated_at: shipped_at)
    ship
  end
end
