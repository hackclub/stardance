# == Schema Information
#
# Table name: sticky_streaks
#
#  id         :bigint           not null, primary key
#  kind       :string           default("first"), not null
#  started_on :date             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_sticky_streaks_on_user_id_and_kind  (user_id,kind) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class StickyStreak < ApplicationRecord
  # A 21-day challenge: keep the daily coding streak alive and each day unlocks
  # that day's sticker. Progress is derived from streak_activities rather than
  # stored, so a late Hackatime backfill retroactively rescues a day instead of
  # leaving the run wrongly failed.
  #
  # Everyone gets a first run. Break it and you get one restart, which skips
  # the stickers already taken home and supersedes the broken run. Reach day 21
  # on either and a second streak opens up: the same 21 days, but it pays out
  # on SECOND_REWARD_DAYS only, from its own reward track.
  LENGTH = 21
  SECOND_REWARD_DAYS = [ 7, 14, 21 ].freeze

  class NotClaimable < StandardError; end

  # The gate passed to the shop when redeeming one day's sticker, so the claim
  # goes through the normal item page (address picker and all) rather than a
  # separate order path.
  DayClaim = Data.define(:sticky_streak, :day)

  DayStat = Data.define(:day, :successful, :in_progress, :potential) do
    def total = successful + in_progress + potential
  end

  has_paper_trail

  # Prefixed because both "first" and "second" are ActiveRecord finders.
  enum :kind, { first: "first", retry: "retry", second: "second" }, prefix: true

  belongs_to :user
  has_many :claims, class_name: "StickyStreakClaim", dependent: :destroy

  validates :user_id, uniqueness: { scope: :kind }
  validates :started_on, presence: true

  # Whether the challenge is switched on for someone. Every surface that shows
  # or redeems a run goes through User#current_sticky_streaks, which reads this,
  # so the flag has one gate rather than a check per surface.
  def self.enabled_for?(user) = user.present? && Flipper.enabled?(:sticky_streaks, user)

  # The days a track can carry a sticker on at all.
  def self.reward_days_for(track) = track.to_s == "second" ? SECOND_REWARD_DAYS : (1..LENGTH).to_a

  def date_for(day) = started_on + (day - 1)

  def day_for(date) = (date.to_date - started_on).to_i + 1

  def last_date = date_for(LENGTH)

  def covers?(date) = (started_on..last_date).cover?(date)

  # Which day-to-item map this run pays from.
  def track = kind_second? ? "second" : "standard"

  # Days this run can still pay out on: the track's days, less the ones whose
  # sticker the user already took home on the run this one restarts.
  def reward_days
    @reward_days ||= self.class.reward_days_for(track).to_set - days_claimed_before_restart
  end

  # A broken first run is closed out the moment its owner restarts. The days
  # they never got round to claiming are forfeited, and only the stickers they
  # actually took home stay on the calendar.
  def superseded?
    return @superseded if defined?(@superseded)

    @superseded = kind_first? && user.sticky_streaks.kind_retry.exists?
  end

  # Dates the run still dresses up in the calendar. A missed day ends the
  # challenge, so it and everything after it go back to being ordinary streak
  # days rather than showing stickers that can never be earned. Derived from
  # missed_day like everything else, so a late Hackatime backfill that rescues
  # the day brings the stickers back with it.
  def decorates?(date)
    return false unless covers?(date)

    day = day_for(date)
    return false unless reward_days.include?(day)
    return false if missed_day && day >= missed_day
    return claimed_days.include?(day) if superseded?

    true
  end

  # The day the user is on right now, clamped into the window.
  def current_day = day_for(today).clamp(1, LENGTH)

  # Days whose window has closed, so no more coding time can land in them.
  def settled_days = (day_for(today) - 1).clamp(0, LENGTH)

  def completed_days
    @completed_days ||= user.streak_activities.completed
      .for_range(started_on..last_date)
      .pluck(:activity_date)
      .map { |date| day_for(date) }
      .to_set
  end

  # First settled day the user did not hit the goal on. Nil while the run lives.
  def missed_day
    return @missed_day if defined?(@missed_day)
    @missed_day = (1..settled_days).find { |day| !completed_days.include?(day) }
  end

  def failed? = missed_day.present?
  def finished? = !failed? && settled_days >= LENGTH
  def active? = !failed? && !finished?

  def claimed_days
    @claimed_days ||= claims.pluck(:day_number).to_set
  end

  def rewards_by_day
    @rewards_by_day ||= StickyStreakReward.by_day(track)
  end

  def claimable_day?(day)
    return false if superseded?
    return false unless reward_days.include?(day)
    return false if missed_day && day >= missed_day
    return false unless completed_days.include?(day)
    return false if claimed_days.include?(day)

    rewards_by_day.key?(day)
  end

  def claimable_days
    @claimable_days ||= reward_days.sort.select { |day| claimable_day?(day) }
  end

  # Drives the always-visible claim button in the widget.
  def latest_claimable_day = claimable_days.last

  # The next day of this run with a sticker still waiting on it, for the
  # widget's status line. Nil once every remaining day is spoken for.
  def next_reward_day
    (current_day..LENGTH).find do |day|
      reward_days.include?(day) && rewards_by_day.key?(day) && !claimed_days.include?(day)
    end
  end

  # Records the claim for a freshly placed free order, mirroring
  # Mission::PrizeRedemption.record!. The order itself is built by the shop.
  def record_claim!(shop_order:, day:)
    raise NotClaimable, "That day isn't ready to claim yet." unless claimable_day?(day)

    claims.create!(day_number: day, shop_order: shop_order)
  end

  # Per-day funnel across the given runs, for the admin overview: how many
  # people banked that day, how many are living it right now, and how many
  # still have it ahead of them. The three sum to everyone who had not broken
  # before that day, so the bar heights trace the survival curve.
  def self.day_stats(scope = all)
    runs = scope.joins(:user).pluck(:id, :started_on, "users.timezone")
    return (1..LENGTH).map { |day| DayStat.new(day: day, successful: 0, in_progress: 0, potential: 0) } if runs.empty?

    completed = completed_days_by_run(scope)
    today_by_zone = runs.map(&:last).uniq.index_with { |zone| StreakActivity.streak_date_for(Time.current, zone) }

    tallies = { successful: Hash.new(0), in_progress: Hash.new(0), potential: Hash.new(0) }

    runs.each do |id, started_on, timezone|
      done = completed.fetch(id, Set.new)
      current = (today_by_zone[timezone] - started_on).to_i + 1
      settled = (current - 1).clamp(0, LENGTH)
      missed = (1..settled).find { |day| !done.include?(day) }
      last_alive = missed ? missed - 1 : LENGTH

      (1..last_alive).each do |day|
        bucket = if day <= settled then :successful
        elsif day == current then :in_progress
        else :potential
        end
        tallies[bucket][day] += 1
      end
    end

    (1..LENGTH).map do |day|
      DayStat.new(day: day,
                  successful: tallies[:successful][day],
                  in_progress: tallies[:in_progress][day],
                  potential: tallies[:potential][day])
    end
  end

  # Day numbers each run hit the daily goal on, keyed by sticky streak id.
  def self.completed_days_by_run(scope = all)
    scope
      .joins("JOIN streak_activities ON streak_activities.user_id = sticky_streaks.user_id")
      .where("streak_activities.coded_seconds >= ?", StreakActivity::DAILY_GOAL_SECONDS)
      .where("streak_activities.activity_date BETWEEN sticky_streaks.started_on AND sticky_streaks.started_on + CAST(? AS integer)", LENGTH - 1)
      .pluck(:id, Arel.sql("(streak_activities.activity_date - sticky_streaks.started_on) + 1"))
      .each_with_object({}) { |(id, day), acc| (acc[id] ||= Set.new) << day }
  end

  private

  def today = user.streak_today_date

  # Stickers the user already took home on the run this restart replaces, so a
  # restart cannot pay the same day twice.
  def days_claimed_before_restart
    return Set.new unless kind_retry?

    @days_claimed_before_restart ||= user.sticky_streaks.kind_first.first&.claimed_days || Set.new
  end
end
