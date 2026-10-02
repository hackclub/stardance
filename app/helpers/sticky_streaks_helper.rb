module StickyStreaksHelper
  StartCopy = Data.define(:summary, :body, :cta)

  # Wording for each run the challenge can offer, keyed by
  # User#startable_sticky_streak_kind. The 21 in the first run's copy is
  # literal: the plushie is the day 21 reward, so extending the run must not
  # move it.
  START_COPY = {
    first: StartCopy.new(
      summary: "Sticky Streak",
      body: "A #{StickyStreak::LENGTH} day challenge! Keep up your daily streak and get a free sticker " \
            "each day. After 21 days you'll get a free starling plushie, but if you miss a day you're " \
            "out of the challenge!",
      cta: "Start my sticky streak"
    ),
    retry: StartCopy.new(
      summary: "Restart your streak",
      body: "You lost your sticky streak run before reaching the end, but don't worry: you just " \
            "got a second chance! When you click restart, you'll get another #{StickyStreak::LENGTH} days to keep " \
            "coding and try making it to the end. You won't be able to claim any stickers you " \
            "already claimed, but you'll be able to claim new ones! But be warned: this is your " \
            "last chance!",
      cta: "Restart my streak"
    ),
    second: StartCopy.new(
      summary: "Start a second streak",
      body: "You made it all the way to day #{StickyStreak::LENGTH}! Go again for another " \
            "#{StickyStreak::LENGTH} days, with a sticker waiting on " \
            "#{StickyStreak::SECOND_REWARD_DAYS.map { |day| "day #{day}" }.to_sentence}.",
      cta: "Start my second streak"
    )
  }.freeze

  def sticky_streak_start_copy(kind) = START_COPY.fetch(kind)

  # Copy for the claim button when nothing is claimable. The button is always
  # rendered, so this doubles as the run's status line.
  def sticky_streak_idle_claim_label(sticky_streak)
    return "Streak broke on day #{sticky_streak.missed_day}" if sticky_streak.failed?
    return "Challenge complete" if sticky_streak.finished?
    return "Stickers coming soon" if sticky_streak.rewards_by_day.empty?

    next_day = sticky_streak.next_reward_day
    return "Keep your streak going" unless next_day
    return "Code today to unlock day #{next_day}" if next_day == sticky_streak.current_day

    "Next sticker on day #{next_day}"
  end

  # Width of one segment of a day's funnel bar, as a share of all runs.
  def sticky_streak_bar_width(count, total)
    return "0%" if total.to_i.zero?

    "#{(count.to_f / total * 100).round(2)}%"
  end

  # All three funnel numbers for a day, revealed on hovering that day's bar.
  def sticky_streak_day_stat_tooltip(stat)
    "#{stat.successful} successful · #{stat.in_progress} in progress · #{stat.potential} potential"
  end
end
