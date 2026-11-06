require "test_helper"

class ViralityDecisionConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @mention = project_mentions(:virality_pending)
    @project = @mention.project
    @project.update!(ship_status: "approved")
    @project.memberships.find_by!(user: users(:one)).update!(role: :owner)
    @admin = users(:two)
    @admin.update!(granted_roles: [ "admin" ])
    @decision = ViralityDecision.schedule!(mention: @mention, reviewer: @admin, attributes: {
      action: "approve", tier: "good", reason: "Checked repository",
      evidence: { "platform" => "GitHub", "metric_name" => "stars", "metric_value" => "25", "eligibility_confirmed" => "1" }
    })
    travel_to @decision.process_at + 1.second
  end

  teardown do
    travel_back
    ViralityDecision.where(project_mention: @mention).delete_all
    LedgerEntry.where(ledgerable: @project, created_by: Virality::ReconcileBonus::CREATED_BY).delete_all
    User::Achievement.where(achievement_slug: %w[viral_good viral_great]).delete_all
  end

  test "two workers cannot pay the same decision twice" do
    results = race { ViralityDecision.find(@decision.id).process! }
    assert_equal [ false, true ], results.sort_by { |value| value ? 1 : 0 }
    assert_equal 50, entries.sum(:amount)
    assert_equal 1, entries.count
  end

  test "stop and process serialize to one unambiguous outcome" do
    race do |index|
      decision = ViralityDecision.find(@decision.id)
      index.zero? ? decision.cancel!(actor: @admin) : decision.process!
    rescue ArgumentError
      # If processing won the lock, cancelling truthfully reports completion.
      nil
    end
    assert_includes %w[cancelled processed], @decision.reload.status
    assert_equal(@decision.status == "processed" ? 50 : 0, entries.sum(:amount))
    assert_equal(@decision.status == "processed" ? :approved : :pending, @mention.reload.status)
  end

  private

  def entries
    LedgerEntry.where(ledgerable: @project, created_by: Virality::ReconcileBonus::CREATED_BY)
  end

  def race(&work)
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          work.call(index)
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
