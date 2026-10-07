require "test_helper"

class HomeBukuLeaderboardTest < ActionDispatch::IntegrationTest
  setup { Flipper.enable(:bukux3) }
  teardown { Flipper.disable(:bukux3) }

  test "home embeds compact team lists inside the event status box without a separate page link" do
    get home_path
    assert_response :success
    assert_select "turbo-frame#buku_x3_home_status > .buku-x3-status > .buku-leaderboard", count: 1
    assert_select ".buku-leaderboard__team", count: 2
    assert_select ".buku-x3-status__tug .buku-x3-status__note", text: /top five.*limited-edition/
    assert_select "details.buku-leaderboard__details:not([open]) > summary", count: 1
    assert_select ".buku-leaderboard-promo, a[href='/buku_x3/leaderboard']", count: 0
  end

  test "three preview rows per side and remaining ranks inside disclosure keep five prize spots" do
    entries = 7.times.map { |index| BukuX3::Leaderboard::Entry.new(user: users(:one), minutes: 600 - index) }
    board = Struct.new(:teams) { def own(*) = nil }.new({ buku: entries, bean: entries })
    BukuX3::Leaderboard.stub(:new, board) do
      get home_path
      assert_response :success
      %w[buku bean].each do |team|
        assert_select ".buku-leaderboard__team--#{team} .buku-leaderboard__row", count: 3
      end
      assert_select ".buku-leaderboard__details ol[start='4']", count: 2
      assert_select ".buku-leaderboard__details .buku-leaderboard__row", count: 4
      assert_select ".buku-leaderboard__row--prize", count: 10
      %w[buku bean].each do |team|
        assert_select ".buku-leaderboard__row--#{team}.buku-leaderboard__row--first", count: 1
        assert_select ".buku-leaderboard__row--#{team}.buku-leaderboard__row--prize:not(.buku-leaderboard__row--first)", count: 4
      end
      assert_select ".buku-leaderboard__note", count: 0
      assert_select ".buku-leaderboard", text: /top 25 per team|to appear here|ranked by exact minutes/, count: 0
      assert_select ".buku-leaderboard__teaser", count: 0
    end
  end

  test "signed in user's own rank shows inside the disclosure below the prize spots" do
    others = 6.times.map { |index| BukuX3::Leaderboard::Entry.new(user: users(:two), minutes: 600 - index) }
    entries = others + [ BukuX3::Leaderboard::Entry.new(user: users(:one), minutes: 10) ]
    own = BukuX3::Leaderboard::Own.new(team: :buku, entry: entries.last, rank: 7)
    board = Struct.new(:teams, :own_standing) { def own(*) = own_standing }.new({ buku: entries, bean: others }, own)
    sign_in(users(:one))
    BukuX3::Leaderboard.stub(:new, board) do
      get home_path
      assert_response :success
      assert_select ".buku-leaderboard__details .buku-leaderboard__teams--rest .buku-leaderboard__row", count: 4
      assert_select ".buku-leaderboard__details .buku-leaderboard__teams--own .buku-leaderboard__rank", text: "7", count: 1
      assert_select ".buku-leaderboard__details .buku-leaderboard__teams--own .buku-leaderboard__you", count: 1
    end
  end

  test "disabled or actor restricted flag hides lists from unauthorized viewers" do
    Flipper.disable(:bukux3)
    get home_path
    assert_select ".buku-leaderboard", count: 0
    Flipper.enable_actor(:bukux3, users(:one))
    get home_path
    assert_select ".buku-leaderboard", count: 0
    sign_in(users(:one))
    get home_path
    assert_select ".buku-leaderboard", count: 1
  end

  test "event bar shows the winning gradient and neutral ties" do
    event = BukuX3::Event.create!(key: BukuX3::Event::KEY, unlocked_at: 1.day.ago)
    { 0 => "bean", 25 => "bean", 50 => "tie", 75 => "buku", 100 => "buku" }.each do |percent, leader|
      event.update!(destruction_minutes: percent * BukuX3::Event::MINUTES_PER_PERCENT)
      get home_path
      assert_select ".buku-x3-status__rope[data-leader='#{leader}']"
    end
  end
end
