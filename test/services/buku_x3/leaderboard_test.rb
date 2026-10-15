require "test_helper"

class BukuX3LeaderboardTest < ActiveSupport::TestCase
  include BukuX3Ships

  setup do
    @event = BukuX3::Event.create!(key: BukuX3::Event::KEY, unlocked_at: 1.day.ago)
    @one = users(:one)
    @two = users(:two)
    [ @one, @two ].each do |user|
      user.preference.update!(leaderboard_optin: true)
      user.dismiss_thing!(BukuX3RevealComponent::DISMISS_THING)
    end
  end

  test "own chase targets the rank above, or the last listed spot when unranked" do
    entries = [ 600, 300 ].map { |minutes| BukuX3::Leaderboard::Entry.new(user: @two, minutes:) }
    teams = { buku: entries, bean: [] }
    ranked = BukuX3::Leaderboard::Own.new(team: :buku, entry: entries.last, rank: 2)
    assert_equal [ 1, 300 ], ranked.chase(teams)
    unranked = BukuX3::Leaderboard::Own.new(team: :buku, entry: BukuX3::Leaderboard::Entry.new(user: @one, minutes: 0), rank: nil)
    assert_equal [ 2, 300 ], unranked.chase(teams)
    tied = BukuX3::Leaderboard::Own.new(team: :buku, entry: BukuX3::Leaderboard::Entry.new(user: @one, minutes: 600), rank: 2)
    assert_equal [ 1, 1 ], tied.chase(teams)
    assert_nil BukuX3::Leaderboard::Own.new(team: :bean, entry: unranked.entry, rank: nil).chase(teams)
    opted_out = BukuX3::Leaderboard::Own.new(team: :buku, entry: BukuX3::Leaderboard::Entry.new(user: @one, minutes: 900), rank: nil)
    assert_nil opted_out.chase(teams)
  end

  test "sums exact ledger minutes per user and uses recorded teams" do
    contribute(@one, true, 91)
    contribute(@one, true, 30)
    contribute(@two, false, 150)
    assert_equal [ [ @one.id, 121 ] ], rows(:buku)
    assert_equal [ [ @two.id, 150 ] ], rows(:bean)
  end

  test "zeroed corrections and other events do not count" do
    contribution = contribute(@one, true, 120)
    contribute(@two, true, 300, event: BukuX3::Event.create!(key: "other", unlocked_at: 1.day.ago))
    assert_equal [ [ @one.id, 120 ] ], rows(:buku)
    contribution.update!(minutes: 0)
    assert_empty rows(:buku)
  end

  test "public ranking respects opt in, role discovery, linked accounts and bans" do
    contribute(@one, true, 120)
    @one.preference.update!(leaderboard_optin: false)
    assert_empty rows(:buku)
    @one.preference.update!(leaderboard_optin: true)
    @one.reload.update!(things_dismissed: [])
    assert_empty rows(:buku)
    @one.dismiss_thing!(BukuX3RevealComponent::DISMISS_THING)
    @one.update!(banned: true)
    assert_empty rows(:buku)
    @one.update!(banned: false)
    @one.hack_club_identity.destroy!
    assert_empty rows(:buku)
  end

  test "ranks exact totals descending with stable account id tie order" do
    contribute(@one, true, 120)
    contribution = contribute(@two, true, 121)
    assert_equal [ @two.id, @one.id ], rows(:buku).map(&:first)
    contribution.update!(minutes: 120)
    assert_equal [ @one.id, @two.id ].sort, rows(:buku).map(&:first)
  end

  test "no event or inactive event is empty and does not create records" do
    contribute(@one, true, 120)
    @event.update!(unlocked_at: nil)
    assert_no_difference [ "BukuX3::Event.count", "BukuX3::Contribution.count" ] do
      assert_equal({ buku: [], bean: [] }, BukuX3::Leaderboard.new(nil).teams)
      assert_equal({ buku: [], bean: [] }, BukuX3::Leaderboard.new(@event).teams)
    end
  end

  test "limits each team independently to its highest twenty five totals" do
    26.times do |index|
      user = create_user(slack_id: "U_LEADERBOARD_#{index}", display_name: "leaderboard_#{index}")
      user.preference.update!(leaderboard_optin: true)
      user.dismiss_thing!(BukuX3RevealComponent::DISMISS_THING)
      contribute(user, true, index + 1)
    end
    contribute(@two, false, 1)
    assert_equal 26.downto(2).to_a, rows(:buku).map(&:last)
    assert_equal [ [ @two.id, 1 ] ], rows(:bean)
  end

  test "own standing uses the ranked entry or unranked team minutes, and hides before the reveal" do
    team = BukuX3::Assignment.buku?(@one) ? :buku : :bean
    board = BukuX3::Leaderboard.new(@event)
    contribute(@one, team == :buku, 90)

    own = board.own(@one, board.teams)
    assert_equal [ team, 1, 90 ], [ own.team, own.rank, own.entry.minutes ]

    @one.preference.update!(leaderboard_optin: false)
    own = board.own(@one, board.teams)
    assert_equal [ team, nil, 90 ], [ own.team, own.rank, own.entry.minutes ]

    @one.update!(things_dismissed: [])
    assert_nil board.own(@one, board.teams)
    assert_nil board.own(nil, board.teams)
  end

  private

  def rows(team)
    BukuX3::Leaderboard.new(@event).teams.fetch(team).map { |entry| [ entry.user.id, entry.minutes ] }
  end

  def contribute(user, buku, minutes, event: @event)
    review = reviewed_ship(user: user, minutes: [ minutes, 15 ].max, approved: minutes, at: 1.hour.ago)
    event.contributions.create!(user: user, buku: buku, minutes: minutes, shipped_at: 1.hour.ago, ysws_review: review)
  end
end
