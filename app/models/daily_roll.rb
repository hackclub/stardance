# frozen_string_literal: true

# One random roll per user per day, rolled from /rng or the discover-rail
# widget. The day's biggest values top the leaderboard.
# == Schema Information
#
# Table name: daily_rolls
#
#  id           :bigint           not null, primary key
#  reroll_value :integer
#  rolled_on    :date             not null
#  value        :integer          not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_daily_rolls_on_rolled_on_and_value    (rolled_on,value)
#  index_daily_rolls_on_user_id                (user_id)
#  index_daily_rolls_on_user_id_and_rolled_on  (user_id,rolled_on) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class DailyRoll < ApplicationRecord
  # Postgres int4 max — an integer column stores this in the same 4 bytes as
  # a roll of 1, so we may as well use the whole dial.
  MAX_VALUE = 2_147_483_647
  LEADERBOARD_SIZE = 5

  # Coding time (in seconds, on a linked Stardance project, today) that
  # unlocks the one earned reroll. See DailyRollsHelper#reroll_state.
  REROLL_MIN_SECONDS = 300

  # A roll's standing is its own value plus any earned reroll. Summed as
  # bigint in SQL so two near-max int4 rolls (~4.29B total) can't overflow
  # the way `value + reroll_value` would as plain int4.
  TOTAL_SQL = "daily_rolls.value::bigint + COALESCE(daily_rolls.reroll_value, 0)"

  # The Monday rng goes live. Days are numbered from it (day 1, day 2, …);
  # pre-launch test rolls show "day -1".
  LAUNCH_ON = Date.new(2026, 6, 15)

  # How a roll's magnitude is built: append digits one at a time, and after
  # each one flip a coin that's slightly less likely to come up "keep going."
  # The coin starts loaded with KEEP_GOING_WEIGHT heads and gains one tail per
  # digit, so most rolls stay short and the rare long one is the jackpot —
  # which is exactly what makes the digit-by-digit reveal suspenseful (you
  # never know if it's about to stop). Bump the weight for longer numbers.
  KEEP_GOING_WEIGHT = 4
  # Never build past int4's digit count; the magnitude is clamped to MAX_VALUE.
  MAX_DIGITS = MAX_VALUE.to_s.length

  # Throwaway aside about a roll, keyed to how big the number got. Each tier
  # has a few casual variants; one is picked per roll (see #flavor). Most rolls
  # land in the bottom tiers. Thresholds are checked high-to-low.
  FLAVORS = [
    [ MAX_VALUE,     [ "no way, the max", "literally the maximum??", "ok that shouldn't happen 🫨" ] ],
    [ 1_000_000_000, [ "whoa, huge", "BILLIONS", "ok that's massive 🤯" ] ],
    [ 100_000_000,   [ "really big number", "huge", "ok big number 👀" ] ],
    [ 1_000_000,     [ "big number", "IS BIG NUMBER 🫨", "millions, nice" ] ],
    [ 100_000,       [ "ooh, six figures", "that's a great roll", "really nice one 👀" ] ],
    [ 1_000,         [ "ooh, thousands", "that's a good one", "nice, getting up there" ] ],
    [ 100,           [ "lowkey not bad", "decent actually", "kinda solid" ] ],
    [ 10,            [ "pretty small", "smallish", "kinda small ngl" ] ],
    [ 1,             [ "wow tiny number", "tiny lol", "so small 😭" ] ],
    [ 0,             [ "ouch, zero", "a literal zero 💀", "zero?? unlucky" ] ]
  ].freeze

  # Colour tier for the number, by magnitude: the dim majority stays muted and
  # the rare big roll glows. Shared by the rail widget and the /rng hero.
  TONES = [
    [ 1_000_000, "cosmic" ],
    [ 10_000,    "high" ],
    [ 100,       "mid" ],
    [ 0,         "low" ]
  ].freeze

  belongs_to :user

  # A roll is generated once, server-side, and is never editable afterwards —
  # no re-numbering an existing roll through any code path. One-per-day is
  # enforced by the unique [user_id, rolled_on] index plus .roll!.
  attr_readonly :value, :rolled_on, :user_id

  validates :value, presence: true,
                    numericality: { only_integer: true, in: 0..MAX_VALUE }
  validates :rolled_on, presence: true, uniqueness: { scope: :user_id }

  scope :on, ->(date) { where(rolled_on: date) }
  # Leaderboard order: biggest total first, earliest roll wins ties.
  scope :ranked, -> { order(Arel.sql("(#{TOTAL_SQL}) DESC, daily_rolls.created_at ASC")) }

  # Rolls for the user today, or returns their existing roll if they already
  # did. Safe under concurrent clicks thanks to the unique [user, date] index.
  def self.roll!(user)
    create!(user: user, value: random_value, rolled_on: Date.current)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    find_by!(user: user, rolled_on: Date.current)
  end

  # A value whose digit count is itself random (see KEEP_GOING_WEIGHT). The
  # first digit is a sure thing; each subsequent one is a coin flip that gets
  # longer odds. Always positive; clamped to MAX_VALUE.
  def self.random_value
    digits = +""
    tails = 0
    loop do
      break unless rand(KEEP_GOING_WEIGHT + tails) < KEEP_GOING_WEIGHT

      digits << rand(10).to_s
      tails += 1
      break if digits.length >= MAX_DIGITS
    end

    [ digits.to_i, MAX_VALUE ].min
  end

  def self.for_today(user)
    find_by(user: user, rolled_on: Date.current)
  end

  # Ties go to whoever rolled first. limit + offset keep a busy day's board
  # paginated so it never loads every roll at once. Ordered by the summed
  # total (first roll + reroll), so a reroll can lift you up the board.
  def self.leaderboard(date = Date.current, limit: LEADERBOARD_SIZE, offset: 0)
    on(date).ranked.limit(limit).offset(offset).includes(:user)
  end

  def rank
    self.class.on(rolled_on)
        .where("(#{TOTAL_SQL}) > :t OR ((#{TOTAL_SQL}) = :t AND daily_rolls.created_at < :at)", t: total, at: created_at)
        .count + 1
  end

  # The number that represents this roll on the board: the first roll plus
  # any earned reroll. reroll_value is nil until the user spends their reroll.
  def total
    value + reroll_value.to_i
  end

  def rerolled?
    reroll_value.present?
  end

  # One variant from the matching tier, stable per roll (seeded by id, or by
  # total before it's saved) so it doesn't reshuffle on every page load.
  # Keyed to the total so a reroll's bigger number gets a bigger-tier quip.
  def flavor
    variants = FLAVORS.find { |threshold, _| total >= threshold }&.last
    variants && variants[(id || total) % variants.size]
  end

  def tone
    TONES.find { |threshold, _| total >= threshold }&.last
  end

  # "day 1", "day 2", … counting from LAUNCH_ON; "day -1" before launch.
  def day_label
    number = rolled_on < LAUNCH_ON ? -1 : (rolled_on - LAUNCH_ON).to_i + 1
    "day #{number}"
  end
end
