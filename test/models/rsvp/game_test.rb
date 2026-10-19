# == Schema Information
#
# Table name: rsvp_games
#
#  id         :bigint           not null, primary key
#  board      :string           default("---------"), not null
#  move_count :integer          default(0), not null
#  status     :integer          default("in_progress"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  rsvp_id    :bigint           not null
#
# Indexes
#
#  index_rsvp_games_on_rsvp_id             (rsvp_id)
#  index_rsvp_games_on_rsvp_id_and_status  (rsvp_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (rsvp_id => rsvps.id)
#
require "test_helper"

class Rsvp::GameTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.fixture_sets = {}

  setup do
    @rsvp = Rsvp.create!(email: "player@example.com")
    @game = Rsvp::Game.start_for(@rsvp)
  end

  test "starts in_progress with empty board and zero moves" do
    assert @game.in_progress?
    assert_equal "---------", @game.board
    assert_equal 0, @game.move_count
  end

  test "valid user move marks the cell and triggers a bot move" do
    @game.play_user_move(4)
    @game.reload

    assert_equal "X", @game.board[4]
    assert_equal 2, @game.move_count
    assert_equal 1, @game.board.count("O")
  end

  test "invalid (out-of-range) move returns :invalid and does not change state" do
    before = @game.board.dup
    assert_equal :invalid, @game.play_user_move(99)
    assert_equal before, @game.reload.board
    assert_equal 0, @game.move_count
  end

  test "invalid (occupied) move returns :invalid" do
    @game.play_user_move(4)
    @game.reload
    occupied_index = @game.board.index("X")
    assert_equal :invalid, @game.play_user_move(occupied_index)
  end

  test "user wins by completing a row" do
    @game.update!(board: "XX-OO----", move_count: 4)
    @game.play_user_move(2)

    assert_predicate @game.reload, :user_won?
    assert_equal [ 0, 1, 2 ], @game.winner_line
  end

  test "draw detected when board fills with no winner" do
    @game.update!(board: "XOXXOOOX-", move_count: 8)
    @game.play_user_move(8)

    assert_predicate @game.reload, :draw?
  end

  test "moves on a finished game return :invalid" do
    @game.update!(status: :user_won)
    assert_equal :invalid, @game.play_user_move(0)
  end

  test "current_for returns latest in_progress game" do
    finished = Rsvp::Game.start_for(@rsvp)
    finished.update!(status: :draw)

    assert_equal @game, Rsvp::Game.current_for(@rsvp)
  end
end
