require "test_helper"

class Virality::ReconcileBonusTest < ActiveSupport::TestCase
  setup do
    @project = projects(:one)
    @project.update!(ship_status: "approved")
    @user = users(:one)
    @project.memberships.find_by!(user: @user).update!(role: :owner)
    @mention = project_mentions(:virality_pending)
    @mention.update!(approved_at: Time.current, approved_tier: "great")
    @ship = Post::ShipEvent.create!(body: "A reviewed release", uploading_attachments: true,
      certification_status: "approved", hours_at_payout: 10, payout_basis_percentile: 100,
      multiplier: 20, payout: 200, payout_blessing: "neutral")
    Post.create!(project: @project, user: @user, postable: @ship)
    @service = Virality::ReconcileBonus.new(@project)
  end

  test "Great uses saved percentiles and pays only the extra plus one flat bonus" do
    @ship.update!(overall_percentile: 10)
    result = @service.call
    assert_equal 150, result[:delta]
    assert_equal 200, @ship.reload.payout
    assert_equal 20, @ship.multiplier
    assert_equal 100, @ship.payout_basis_percentile
    assert_equal 0, @service.call[:delta]
    assert_equal 150, paid
  end

  test "blessings and curses use original rounding and never a current verdict" do
    @ship.update!(payout_blessing: "blessed", payout: 240)
    assert_equal 120, @ship.virality_extra_payout
    @ship.update!(payout_blessing: "cursed", payout: 100)
    assert_equal 50, @ship.virality_extra_payout
  end

  test "the low end stays at one stardust per hour" do
    @ship.update!(payout_basis_percentile: 0, multiplier: 1, payout: 10)
    assert_equal 0, @ship.virality_extra_payout
    assert_equal 50, @service.call[:delta]
  end

  test "unpaid ships wait and later reconciliation pays their difference" do
    @ship.update!(payout: nil)
    assert_equal 50, @service.call[:delta]
    @ship.update!(payout: 200)
    ReconcileViralityBonusJob.perform_now(@project.id)
    assert_equal 150, paid
  end

  test "Good to Great is an upgrade without another flat bonus" do
    @mention.update!(approved_tier: "good")
    assert_equal 50, @service.call[:delta]
    @mention.update!(approved_tier: "great")
    assert_equal 100, @service.call[:delta]
    assert_equal 150, paid
  end

  test "reversing Great preserves Good earned by another mention" do
    @service.call
    project_mentions(:virality_second).update!(approved_at: Time.current, approved_tier: "good")
    @mention.update!(approved_at: nil, approved_tier: nil)
    assert_equal(-100, @service.call[:delta])
    assert_equal 50, paid
    assert @user.reload.achievements.exists?(achievement_slug: "viral_good")
    refute @user.achievements.exists?(achievement_slug: "viral_great")
  end

  test "the project cap includes the flat bonus" do
    @ship.update!(hours_at_payout: 1_000, payout: 20_000)
    assert_equal 5_000, @service.call[:delta]
    assert_equal 0, @service.call[:delta]
  end

  test "missing saved basis fails instead of guessing" do
    @ship.update!(payout_basis_percentile: nil)
    assert_raises(ArgumentError) { @service.call }
    assert_equal 0, paid
  end

  test "safe links omit javascript and preserve multiple evidence urls" do
    @mention.update!(url: "javascript:alert(1), https://example.com/a https://example.com/b")
    assert_equal [ "https://example.com/a", "https://example.com/b" ], @mention.evidence_urls
  end

  private

  def paid
    LedgerEntry.where(ledgerable: @project, created_by: Virality::ReconcileBonus::CREATED_BY).sum(:amount)
  end
end
