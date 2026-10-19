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
class Rsvp::Game < ApplicationRecord
  self.table_name = "rsvp_games"

  belongs_to :rsvp

  enum :status, { in_progress: 0, user_won: 1, bot_won: 2, draw: 3 }

  USER  = "X".freeze
  BOT   = "O".freeze
  EMPTY = "-".freeze
  WINS  = [
    [ 0, 1, 2 ], [ 3, 4, 5 ], [ 6, 7, 8 ],
    [ 0, 3, 6 ], [ 1, 4, 7 ], [ 2, 5, 8 ],
    [ 0, 4, 8 ], [ 2, 4, 6 ]
  ].freeze
  MAX_MOVES = 9

  def self.current_for(rsvp) = rsvp.games.in_progress.order(created_at: :desc).first
  def self.start_for(rsvp)   = rsvp.games.create!

  def play_user_move(cell)
    return :invalid unless valid_move?(cell)

    apply!(cell, USER)
    return :ended unless in_progress?

    play_bot_move
    in_progress? ? :continued : :ended
  end

  def grid = board.chars.each_slice(3).to_a

  def board_text
    grid.map { |row| " " + row.map { |c| c == EMPTY ? " " : c }.join(" | ") }.join("\n-----------\n")
  end

  def outcome
    case status
    when "user_won" then "you won"
    when "bot_won"  then "i won"
    when "draw"     then "draw"
    end
  end

  def winner_line
    WINS.find { |a, b, c| board[a] != EMPTY && board[a] == board[b] && board[b] == board[c] }
  end

  private

  def valid_move?(cell)
    cell.is_a?(Integer) && cell.between?(0, 8) && in_progress? && board[cell] == EMPTY
  end

  def empty_cells = (0..8).select { |i| board[i] == EMPTY }

  def play_bot_move
    cell = empty_cells.sample
    return unless cell

    apply!(cell, BOT)
  end

  def apply!(cell, mark)
    new_board = board.dup
    new_board[cell] = mark
    self.board = new_board
    self.move_count += 1
    finalize_status(mark)
    save!
  end

  def finalize_status(mark)
    if WINS.any? { |line| line.all? { |i| board[i] == mark } }
      self.status = (mark == USER ? :user_won : :bot_won)
    elsif move_count >= MAX_MOVES
      self.status = :draw
    end
  end
end
