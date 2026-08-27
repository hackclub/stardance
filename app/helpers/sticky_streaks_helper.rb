module StickyStreaksHelper
  # Copy for the claim button when nothing is claimable. The button is always
  # rendered, so this doubles as the run's status line.
  def sticky_streak_idle_claim_label(sticky_streak)
    if sticky_streak.failed?
      "Streak broke on day #{sticky_streak.missed_day}"
    elsif sticky_streak.finished?
      "Challenge complete"
    elsif sticky_streak.rewards_by_day.empty?
      "Stickers coming soon"
    else
      "Code today to unlock day #{sticky_streak.current_day}"
    end
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
