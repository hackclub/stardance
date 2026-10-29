require "test_helper"

class Finality::RaffleConcurrencyTest < ActiveSupport::TestCase
  # Separate connections must see committed records to exercise real row locks.
  self.use_transactional_tests = false

  setup do
    travel_to Finality.window.end + 1.day
    @admin = users(:one)
    @admin.grant_role!(:admin)
    @people = 6.times.map do |i|
      create_user(slack_id: "U_CONCURRENT_DRAW_#{i}", display_name: "concurrent_draw_#{i}", hca_linked: false)
    end
    @ships = @people.map do |person|
      ship = Post::ShipEvent.create!(body: "Concurrent draw test", uploading_attachments: true, certification_status: "approved")
      Post.create!(project: projects(:one), user: person, postable: ship, created_at: Finality.window.begin + 1.hour)
      ship
    end
  end

  teardown do
    Finality::RaffleSelection.delete_all
    Finality::RaffleEntry.delete_all
    Finality::RaffleDraw.delete_all
    PaperTrail::Version.where(item_type: [ "Finality::RaffleDraw", "Finality::RaffleSelection" ]).delete_all
    @ships&.each { |ship| ship.post.destroy! }
    @people&.each(&:destroy!)
    travel_back
  end

  test "simultaneous freeze, roll and reroll requests cannot duplicate results" do
    draws = race { Finality::RaffleDraw.freeze_pool!(actor: @admin) }
    assert_equal 1, draws.map(&:id).uniq.size
    assert_equal 1, Finality::RaffleDraw.count
    assert_equal 6, Finality::RaffleEntry.count

    counts = race { Finality::RaffleDraw.current.roll!(prize_key: "vip", actor: @admin) }
    assert_equal [ 0, 2 ], counts.sort
    draw = Finality::RaffleDraw.current
    assert_equal 2, draw.selections.active.count
    assert_equal 2, draw.selections.active.distinct.count(:user_id)

    previous = draw.selections.first
    replacements = race do
      Finality::RaffleDraw.current.reroll!(selection_id: previous.id, reason: "Staff review", actor: @admin)
    rescue Finality::RaffleDraw::Error => error
      error
    end
    assert_equal 1, replacements.count { |result| result.is_a?(Finality::RaffleSelection) }
    assert_equal 1, replacements.count { |result| result.is_a?(Finality::RaffleDraw::Error) }
    assert previous.reload.voided_at?
    assert_equal 3, draw.selections.count
    assert_equal 2, draw.selections.active.count
    assert_equal 1, previous.versions.where(event: "reroll_raffle_selection").count
  end

  private

  def race(&work)
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          work.call
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.map(&:value)
  ensure
    threads&.each(&:join)
  end
end
