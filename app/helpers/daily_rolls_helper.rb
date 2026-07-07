# frozen_string_literal: true

module DailyRollsHelper
  # "1,234" — rolls are always positive, so they're shown plainly.
  def formatted_roll_value(value)
    number_with_delimiter(value)
  end

  # Whether the earned-reroll feature is live for this user.
  def reroll_enabled?(user)
    Flipper.enabled?(:rng_reroll, user)
  end

  # State of the earned reroll for today's roll:
  #   :used     — already rerolled today
  #   :unlocked — coded more than REROLL_MIN_SECONDS today on a linked project
  #   :locked   — hasn't coded enough yet
  # nil when there's nothing to reroll (no user, or they haven't rolled yet).
  def reroll_state(user, roll)
    return nil if user.nil? || roll.nil?
    return :used if roll.rerolled?

    reroll_coded_seconds(user) > DailyRoll::REROLL_MIN_SECONDS ? :unlocked : :locked
  end

  # Seconds the user has coded today on a linked Stardance project (the gate
  # for unlocking the reroll). Read from the cached streak activity.
  def reroll_coded_seconds(user)
    user&.streak_today_activity&.coded_seconds.to_i
  end

  # Tooltip on the locked reroll button: what to do to unlock it.
  def reroll_locked_hint
    "Code 5 min on a Stardance project today to unlock a reroll which will increase your number!"
  end

  # The copy-to-share blurb, e.g.
  #   stardance rng day 1
  #   🎲 50 · ranked #150 so far
  #   https://…/rng
  def roll_share_text(roll)
    "stardance rng #{roll.day_label}\n" \
      "🎲 #{formatted_roll_value(roll.total)} · ranked ##{roll.rank} so far\n" \
      "#{rng_url}"
  end

  def rng_date_label(date, today: Date.current)
    return "Today" if date == today
    return "Yesterday" if date == today - 1

    date.strftime(date.year == today.year ? "%B %-d" : "%B %-d, %Y")
  end

  # The next daily reset (local midnight), and a "Xh Ymin" string until then.
  # The countdown Stimulus controller keeps the rendered value live.
  def rng_reset_at
    Time.current.beginning_of_day + 1.day
  end

  def time_until_rng_reset(now = Time.current)
    seconds = [ (rng_reset_at - now).to_i, 0 ].max
    "#{seconds / 3600}h #{seconds % 3600 / 60}min"
  end

  # Link to a given day's page; today gets the canonical bare /rng.
  def rng_date_path(date, today: Date.current)
    date == today ? rng_path : rng_path(date: date.iso8601)
  end

  # Link to a specific leaderboard page within a day; omits default params so
  # page 1 of today stays the canonical bare /rng.
  def rng_page_path(date, page, today: Date.current)
    params = {}
    params[:date] = date.iso8601 unless date == today
    params[:page] = page unless page == 1
    rng_path(params)
  end
end
